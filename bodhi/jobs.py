# $Id: $
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

"""
    This module is for functions that are to be executed on a regular basis
    using the TurboGears scheduler.
"""

import os
import logging
import subprocess

from os.path import isdir, realpath, dirname, join, islink, exists
from datetime import datetime
from turbogears import scheduler, config
from sqlobject import SQLObjectNotFound
from sqlobject.sqlbuilder import AND

from bodhi import mail
from bodhi.buildsys import get_session
from bodhi.util import get_age_in_days
from bodhi.model import Release, PackageUpdate, BuildRootOverride, PackageBuild

log = logging.getLogger(__name__)


def clean_repo():
    """
    Clean up our mashed_dir, removing all referenced repositories
    """
    log.info("Starting clean_repo job")
    liverepos = []
    repos = config.get('mashed_dir')
    mash_locks = set()
    for release in Release.select():
        lock = join(repos, 'MASHING-%s' % release.id_prefix)
        mash_locks.add(lock)
        if exists(lock):
            log.info("Mash in progress.  Aborting clean_repo job")
            return
    for release in [rel.name.lower() for rel in Release.select()]:
        # TODO: keep the 2 most recent repos!
        for repo in [release + '-updates', release + '-updates-testing']:
            liverepos.append(dirname(realpath(join(repos, repo))))
    for repo in [join(repos, repo) for repo in os.listdir(repos)]:
        if 'repodata' in repo: # skip our repodata caches
            continue
        if not islink(repo) and isdir(repo):
            fullpath = realpath(repo)
            if fullpath not in liverepos:
                log.info("Removing %s" % fullpath)
                subprocess.call(['rm', '-fr', fullpath])

        # Bail out if a push started in the middle of this job
        for lock in mash_locks:
            if exists(lock):
                log.warning('Mash lock detected!  Stopping clean_repo job.')
                return

    log.info("clean_repo complete!")


def nagmail():
    """
    Nag the submitters of updates based on a list of queries
    """
    log.info("Starting nagmail job!")
    queries = [
            ('old_testing', PackageUpdate.select(
                                    AND(PackageUpdate.q.status == 'testing',
                                        PackageUpdate.q.request == None)),
             lambda update: update.days_in_testing),
            ('old_pending', PackageUpdate.select(
                                    AND(PackageUpdate.q.status == 'pending',
                                        PackageUpdate.q.request == None)),
             lambda update: get_age_in_days(update.date_submitted)),
    ]
    oldname = None
    mail_admin = False
    #mail_proventesters = False

    for name, query, date in queries:
        for update in query:
            if date(update) > 14:
                if update.nagged:
                    if update.nagged.has_key(name) and update.nagged[name]:
                        if (datetime.utcnow() - update.nagged[name]).days < 7:
                            continue # Only nag once a week at most
                    nagged = update.nagged
                else:
                    nagged = {}

                if update.critpath:
                    if update.critpath_approved:
                        continue
                    else:
                        oldname = name
                        name = 'old_testing_critpath'
                        mail_admin = True
                        #mail_proventesters = True

                log.info("[%s] Nagging %s about %s" % (name, update.submitter,
                                                       update.title))
                mail.send(update.submitter, name, update)
                if mail_admin:
                    mail.send_admin(name, update)
                    mail_admin = False
                #if mail_proventesters:
                #    mail.send(config.get('proventesters_email'), name, update)
                #    mail_proventesters = False

                nagged[name] = datetime.utcnow()
                update.nagged = nagged

                if oldname:
                    name = oldname
                    oldname = None

    log.info("nagmail complete!")


def fix_bug_titles():
    """
    Go through all bugs with invalid titles and see if we can re-fetch them.
    If bugzilla is down, then bodhi simply replaces the title with
    'Unable to fetch bug title' or 'Invalid bug number'.  So lets occasionally
    see if we can re-fetch those bugs.
    """
    from bodhi.model import Bugzilla
    from sqlobject.sqlbuilder import OR
    log.debug("Running fix_bug_titles job")
    for bug in Bugzilla.select(
                 OR(Bugzilla.q.title == 'Invalid bug number',
                    Bugzilla.q.title == 'Unable to fetch bug title')):
        bug.fetch_details()


def cache_release_data():
    """Refresh some commonly used peices of information.

    This entails things like all releases, and how many updates exist for
    each type of update for each release.  These pieces of information are in
    the master template, and we want to avoid hitting the db multiple times
    for each visit (as much as possible).

    """
    log.info("Caching release metrics")
    from bodhi.model import Releases
    try:
        Releases().update()
    except Exception, e:
        log.exception(e)
    log.info("Release cache complete")


def refresh_metrics():
    """ Refresh all of our graphs and metrics """
    from bodhi.metrics import MetricData
    try:
        MetricData().refresh()
    except Exception, e:
        log.exception(e)


def approve_testing_updates():
    """
    Scan all testing updates and approve ones that have met the per-release
    testing requirements.

    https://intranet.network-box.com/wiki/index.php/Package_update_acceptance_criteria
    """
    log.info('Running approve_testing_updates job...')
    for update in PackageUpdate.select(
            AND(PackageUpdate.q.status == 'testing',
                PackageUpdate.q.request == None)):
        # If this release does not have any testing requirements, skip it
        if not update.release.mandatory_days_in_testing:
            continue
        # If this has already met testing requirements, skip it
        if update.met_testing_requirements:
            continue
        if update.meets_testing_requirements:
            log.info('%s now meets testing requirements' % update.title)
            update.comment(
                config.get('testing_approval_msg') % update.days_in_testing,
                author='bodhi')
    log.info('approve_testing_updates job complete.')


def expire_buildroot_overrides():
    """ Iterate over all of the buildroot overrides, expiring appropriately """
    log.info('Running expire_buildroot_overrides job')
    now = datetime.utcnow()
    for override in BuildRootOverride.select(BuildRootOverride.q.date_expired == None):
        if override.expiration and now > override.expiration:
            log.info('Automatically expiring buildroot override: %s' %
                     override.build)

            # Hack around overrides w/o a release.
            if not override.release:
                try:
                    build = PackageBuild.byNvr(override.build)
                    if len(build.updates):
                        override.release = build.updates[0].release
                        print "Fixing release for %s: %s" % (override.build,
                                override.release.name)
                        override.untag()
                        override.date_expired = now
                    else:
                        log.error("Cannot determine release for override: %s" % override)
                except SQLObjectNotFound:
                    log.error("Cannot find build for override: %s" % override)
            else:
                override.untag()
                override.date_expired = now

    log.info('expire_buildroot_overrides job complete!')

def clean_pending_tags():
    """ Clean up any stray pending tags """
    koji = get_session()
    for release in Release.select():
        log.info("Finding all stray pending-testing builds...")
        if release.name.startswith('EL'):
            continue

        tag = release.pending_testing_tag
        tagged = [build['nvr'] for build in koji.listTagged(tag)]
        for nvr in tagged:
            try:
                build = PackageBuild.byNvr(nvr)
                for update in build.updates:
                    if update.status in ('testing', 'stable', 'obsolete'):
                        log.info("%s %s" % (nvr, update.status))
                        log.info("Untagging %s" % nvr)
                        koji.untagBuild(tag, nvr, force=True)
            except SQLObjectNotFound:
                log.info("Can't find build for %s" % nvr)
                log.info("Untagging %s" % nvr)
                koji.untagBuild(tag, nvr, force=True)

        log.info("Finding all stray pending-stable builds...")
        tag = release.pending_stable_tag
        tagged = [build['nvr'] for build in koji.listTagged(tag)]
        for nvr in tagged:
            try:
                build = PackageBuild.byNvr(nvr)
                for update in build.updates:
                    if update.status in ('pending', 'obsolete', 'stable'):
                        log.info("%s %s" % (nvr, update.status))
                        log.info("Untagging %s" % nvr)
                        koji.untagBuild(tag, nvr, force=True)
            except SQLObjectNotFound:
                log.info("Untagging %s" % nvr)
                koji.untagBuild(tag, nvr, force=True)


def schedule():
    """ Schedule our periodic tasks """

    jobs = config.get('jobs')

    # Weekly repository cleanup
    if 'clean_repo' in jobs:
        log.debug("Scheduling clean_repo job")
        scheduler.add_interval_task(action=clean_repo,
                                    taskname="Clean update repositories",
                                    initialdelay=604800,
                                    interval=604800)

    # Daily nagmail
    if 'nagmail' in jobs:
        log.debug("Scheduling nagmail job")
        scheduler.add_weekday_task(action=nagmail,
                                   weekdays=range(1,8),
                                   timeonday=(0,0))

    # Fix invalid bug titles
    if 'fix_bug_titles' in jobs:
        log.debug("Scheduling fix_bug_titles job")
        scheduler.add_interval_task(action=fix_bug_titles,
                                    taskname='Fix bug titles',
                                    initialdelay=1200,
                                    interval=604800)

    # Warm up some data caches
    if 'cache_release_data' in jobs:
        log.debug("Scheduling cache_release_data job")
        scheduler.add_interval_task(action=cache_release_data,
                                    taskname='Cache release data',
                                    initialdelay=0,
                                    interval=43200)

    # If we're the masher, then handle the costly metric regenration
    if not config.get('masher') and 'refresh_metrics' in jobs:
        log.debug("Scheduling refresh_metrics job")
        scheduler.add_interval_task(action=refresh_metrics,
                                    taskname='Refresh our metrics',
                                    initialdelay=7200,
                                    interval=86400)

    # Approve updates that have been in testing for a certain amount of time
    if 'approve_testing_updates' in jobs:
        log.warning("Not scheduling approve_testing_updates job.\nThis is "
                    "supposed to send nagmails when an update has spent enough"
                    " time in\ntesting. However, our update policy does not "
                    "care about the amount of time an\nupdate has spent in "
                    "testing: each update MUST be manually approved by a "
                    "human.\nAs such, a daily nagmails that all update have "
                    "spent the required (0) days in\ntesting would be both "
                    "useless and infuriating.")

    # Automatically expire buildroot overrides
    if 'expire_buildroot_overrides' in jobs:
        log.debug("Scheduling expire_buildroot_overrides job")
        scheduler.add_interval_task(action=expire_buildroot_overrides,
                                   # Run every hour
                                   initialdelay=3600,
                                   interval=3600)
                                   #weekdays=range(1,8),
                                   #timeonday=(0,0))

    # Automatically clean up stray pending tags
    if 'clean_pending_tags' in jobs:
        log.debug("Scheduling clean_pending_tags job")
        scheduler.add_interval_task(action=clean_pending_tags,
                                   # Run every 6 hours
                                   initialdelay=21600,
                                   interval=21600)
