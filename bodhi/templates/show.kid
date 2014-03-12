<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

<html xmlns="http://www.w3.org/1999/xhtml" xmlns:py="http://purl.org/kid/ns#"
    py:extends="'master.kid'">

<head>
    <meta content="text/html; charset=UTF-8" http-equiv="content-type"
            py:replace="''"/>
        <title>${update.title}</title>
    <script src="${tg.url('/static/js/jquery.dimensions.js')}" type="text/javascript"></script>
    <script src="${tg.url('/static/js/jquery.tooltip.js')}" type="text/javascript"></script>
    <script src="${tg.url('/static/js/chili-1.7.pack.js')}" type="text/javascript"></script>
    <script src="${tg.url('/static/js/jquery.bgiframe.js')}" type="text/javascript"></script>
</head>

<?python
from cgi import escape
from bodhi import util
from turbogears import identity, config
from markdown import markdown
import re

koji_url = config.get('koji_url')

## Link to build info and logs
buildinfo = ''
for build in update.builds:
    nvr = util.get_nvr(build.nvr)
    buildinfo += '<a href="%s/koji/search?terms=%s&amp;type=build&amp;match=glob">%s</a> (<a href="%s/packages/%s/%s/%s/data/logs">logs</a>)<br/>' % (koji_url, build.nvr, build.nvr, koji_url, nvr[0], nvr[1], nvr[2])

## Make the package name linkable in the n-v-r
title = ''
if len(update.builds) > 2:
    for build in update.builds:
        title += util.link(build.package.name, '/%s' % build.package.name)+', '
else:
    for build in update.builds:
        nvr = util.get_nvr(build.nvr)
        title += "<a href=\"" + util.url('/%s' % nvr[0]) + "\">" + nvr[0] + "</a>-" + '-'.join(nvr[-2:]) + ", "
title = title[:-2]

critpath = update.critpath and 'critical path ' or ''

release = util.link(update.release.long_name, '/' + update.release.name)
submitter = util.link(update.submitter, '/user/' + update.submitter)

reg = re.compile(r'(^[-*] .*(?:\n[-*] .*)*)', re.MULTILINE)
notes = markdown(reg.sub(r'\n\1\n', escape(update.notes)))

if update.karma < 0: karma = -1
elif update.karma > 0: karma = 1
else: karma = 0
karma = "<img src=\"%s\" align=\"top\" /> <b>%d</b>" % (tg.url('/static/images/karma%d.png' % karma), update.karma)

statusinfo = {
    'pending': 'Pending - <b>This update has yet to be pushed to a repository.  If it has a "testing" request, that means that it is in the queue to be pushed to the updates-testing repository. This process requires a release engineer to sign the packages and manually trigger the push, which usually occurs on a daily basis.</b>',
    'testing': 'Testing - <b>This update is currently in the updates-testing repository. Once it meets the minimum karma or time-in-testing requirements, it can then be pushed to the stable updates repository. If wish to install this update and you do not have the updates-testing repo enabled, you can run `yum --enablerepo=%s install package`.</b>' % (update.release.collection_name == 'Fedora EPEL' and 'epel-testing' or 'updates-testing',),
    'obsolete': 'Obsolete - <b>This update has been obsoleted by a newer update.</b>',
    'stable': 'Stable - <b>This update has been released to the stable updates repository and is available for all users to install via the standard update mechanisms.</b>',
}
?>

<body>
<center>
<table width="97%">
   <tr>
        <td>
            <div class="show"><img align="absmiddle" src="${tg.url('/static/images/%s.png' % update.type)}" alt="${update.type}"/> ${XML(title)} ${critpath}${update.type} update</div>
        </td>

        <!-- update options -->
        <span py:if="not tg.identity.anonymous and util.authorized_user(update, identity)">
            <td align="right" width="50%" valign="bottom">
                <table cellspacing="7">
                    <tr>
                        <span py:if="not update.pushed">
                            <span py:if="'security_respons' in tg.identity.groups and update.type == 'security' and not update.approved">
                                <td>
                                    <a href="${util.url('/approve/%s' % update.title)}" class="list"><img src="${tg.url('/static/images/submit.png')}" border="0" />Approve for Stable</a>
                                </td>
                            </span>
                            <span py:if="update.request == None">
                                <span py:if="update.status != 'testing'">
                                    <td>
                                        <a href="${util.url('/request/testing/%s' % update.title)}" class="list">
                                            <img src="${tg.url('/static/images/testing.png')}" border="0"/>
                                            Push to Testing
                                        </a>
                                    </td>
                                </span>

                                <span py:if="update.status != 'stable'">
                                    <span py:if="update.critpath">
                                        <span py:if="update.critpath_approved">
                                            <td>
                                                <a href="${util.url('/request/stable/%s' % update.title)}" class="list">
                                                    <img src="${tg.url('/static/images/submit.png')}" border="0"/>
                                                    Push Critical Path update to Stable
                                                </a>
                                            </td>
                                        </span>
                                    </span>
                                    <span py:if="not update.critpath">
                                        <td>
                                            <a href="${util.url('/request/stable/%s' % update.title)}" class="list">
                                                <img src="${tg.url('/static/images/submit.png')}" border="0"/>
                                                Push to Stable
                                            </a>
                                        </td>
                                    </span>
                                </span>
                                <td>
                                    <a href="${util.url('/confirm_delete?nvr=%s' % update.title)}" class="list">
                                        <img src="${tg.url('/static/images/trash.png')}" border="0"/>
                                        Delete
                                    </a>
                                </td>
                            </span>
                            <td>
                                <a href="${util.url('/edit/%s' % update.title)}" class="list">
                                    <img src="${tg.url('/static/images/edit.png')}" border="0"/>
                                    Edit
                                </a>
                            </td>
                        </span>
                        <span py:if="update.pushed and update.status != 'stable'">
                            <td>
                                <a href="${util.url('/request/unpush/%s' % update.title)}" class="list">
                                    <img src="${tg.url('/static/images/revoke.png')}" border="0"/>
                                    Unpush
                                </a>
                            </td>
                            <span py:if="update.status == 'testing'">
                              <span py:if="update.request == None">
                                  <span py:if="update.critpath">
                                      <span py:if="update.critpath_approved">
                                          <td>
                                              <a href="${util.url('/request/stable/%s' % update.title)}" class="list">
                                                  <img src="${tg.url('/static/images/submit.png')}" border="0"/>
                                                  Mark Critical Path update as Stable
                                              </a>
                                          </td>
                                      </span>
                                  </span>
                                  <span py:if="not update.critpath">
                                      <td>
                                          <a href="${util.url('/request/stable/%s' % update.title)}" class="list">
                                              <img src="${tg.url('/static/images/submit.png')}" border="0"/>
                                              Mark as Stable
                                          </a>
                                      </td>
                                  </span>
                                </span>
                            </span>
                            <td>
                                <a href="${util.url('/edit/%s' % update.title)}" class="list">
                                    <img src="${tg.url('/static/images/edit.png')}" border="0"/>
                                    Edit
                                </a>
                            </td>
                    </span>
                    <span py:if="update.pushed and update.status == 'stable' and 'releng' in tg.identity.groups">
                      <td>
                        <a href="${util.url('/request/unpush/%s' % update.title)}" class="list">
                            <img src="${tg.url('/static/images/revoke.png')}" border="0"/>
                            Unpush
                        </a>
                      </td>
                    </span>
                    <span py:if="update.request != None">
                        <td>
                            <a href="${util.url('/revoke/%s' % update.title)}" class="list">
                                <img src="${tg.url('/static/images/revoke.png')}" border="0"/>
                                Revoke request
                            </a>
                        </td>
                    </span>
                </tr>
            </table>
        </td>
      </span>
    </tr>
</table>
</center>

<table class="show">
    <tr><td class="title">Status:</td><td class="value">${update.status} <span title="${statusinfo[update.status]}" id="statusinfo"><img src="${tg.url('/static/images/i.gif')}" /></span></td></tr>
    <tr py:for="field in (
        ['Release',         XML(release)],
        ['Update ID',       update.updateid],
        ['Builds',          XML(buildinfo)],
        ['Requested',       update.request],
        ['Pushed',          update.pushed],
        ['Date Submitted',  update.date_submitted],
        ['Date Released',   update.date_pushed],
        ['Date Modified',   update.date_modified],
        ['Submitter',       XML(submitter)],
        ['Karma',           XML(karma)],
        ['Stable karma',    update.stable_karma],
        ['Unstable karma',  update.unstable_karma],
        )">
      <div py:if="field[1] != None and field[1] != ''">
          <td class="title"><b>${field[0]}:</b></td>
          <td class="value">${field[1]}</td>
      </div >
    </tr>
    <div py:if="not tg.identity.anonymous and 
                util.authorized_user(update, identity)">
      <tr py:for="title, value in (
            ['Close bugs', update.close_bugs],
            )">
        <div py:if="value and value != ''">
          <td class="title"><b>${title}:</b></td>
          <td class="value">${value}</td>
        </div>
      </tr>
      <tr>
        <div py:if="update.type == 'security'">
          <td class="title"><b>Security Team Approval</b></td>
          <td class="value">${update.approved}</td>
        </div>
      </tr>
    </div>
</table>

<blockquote>
  <div py:if="update.notes">
    <div class="show">Details</div>
    <blockquote>${XML(notes)}</blockquote>
  </div>

  <div py:if="update.bugs">
    <div class="show">Bugs Fixed</div>
    <blockquote>
      <div py:for="bug in update.bugs">
        <?python
        if bug.title:
            title = escape(bug.title.encode('utf8', 'replace'))
        else:
            title = 'Unable to fetch bug title'
        cve = title.split()[0].replace(':', '')
        if cve.startswith('CVE-'):
            title = '<a href="http://cve.mitre.org/cgi-bin/cvename.cgi?name=' + cve + '">' + cve + '</a>' + ': ' + escape(' '.join(title.split()[1:]))
        ?>
        <a href="${bug.get_url()}">${bug.bz_id}</a> - ${XML(title)}
     </div>
    </blockquote>
  </div>

  <div py:if="update.nagged and 'test_cases' in update.nagged.keys() and update.nagged['test_cases']">
    <div class="show">Test Cases</div>
    <ul py:for="test in update.nagged['test_cases']">
      <li><a href="https://intranet.network-box.com/wiki/index.php/${test}">${test.replace('QA:Testcase', '')}</a></li>
    </ul>
  </div>

  <div class="show">Feedback 
    <a href="https://fedoraproject.org/wiki/QA:Update_feedback_guidelines">
        <img src="${tg.url('/static/images/header-faq.png')}" width="28" title="Update feedback guidelines" style="vertical-align:text-bottom"/>
    </a>
  </div>
  <blockquote>
    <div py:if="update.comments">
      <div py:for="comment in update.get_comments()">
          <img py:attrs="{'src' : tg.url('/static/images/comment-%d.png' % comment.karma)}" hspace="3" style="float:left"/>
              <div py:if="comment.anonymous">
                  <div py:if="tg.identity.anonymous">
                      <b>Anonymous Tester</b> - ${comment.timestamp}<br/>
                  </div>
                  <div py:if="not tg.identity.anonymous">
                      <b>${comment.author}</b> (Anonymous) - ${comment.timestamp}<br/>
                  </div>
              </div>
              <div py:if="not comment.anonymous">
                  <b><a href="${tg.url('/user/%s' % comment.author.split(' (')[0])}">${comment.author}</a></b> - ${comment.timestamp}<br/>
              </div>
        <div class="comment-text" py:replace="comment.html_text">Comment</div>
      </div>
    </div>
    <div py:if="not update.comments">
      There are no comments on this update.
    </div>
    <h3 id="addcomment" style="display: none"><a href="#" onclick="$('#addcomment').hide(); $('#commentform').show('slow'); return false;">Add a comment >></a></h3>
    <div id="commentform">
      <h3>Add a comment</h3>
      ${comment_form.display(value=values)}
    </div>
  </blockquote>

</blockquote>
<script type="text/javascript">
  $(document).ready(function(){
    $('#commentform').hide();
    $('#addcomment').show();

    $('#statusinfo').Tooltip({
        event: 'click',
        extraClass: "pretty fancy pretty-big fancy-big",
        showBody: " - ",
        left: 5,
        top: -15,
        fixPNG: true,
    });

  });
</script>
</body>
</html>
