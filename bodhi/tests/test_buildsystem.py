# $Id: $

import turbogears
from turbogears import config, database


turbogears.update_config(configfile='bodhi.cfg', modulename='bodhi.config')
database.set_db_uri("sqlite:///:memory:")


class TestBuildsystem(object):

    def test_valid_buildsys(self):
        buildsys = config.get('buildsystem')
        assert buildsys in ('koji', 'dev'), "buildsystem must be either 'koji' or 'dev'"

    def test_session(self):
        from bodhi.buildsys import get_session
        session = get_session()
        assert session
