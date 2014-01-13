# [NBRS] Completely shunt all fedmsg stuff in Bodhi
#
# We don't use fedmsg, and packaging it in NBRS 5 would introduce tons of
# dependency.
#
# This is a bit of a hack, but it's much simpler.
class FedmsgBlackHole(object):
    def noop(self, *args, **kwargs):
        pass

    def __getattr__(self, name):
        return self.noop

import sys
sys.modules["fedmsg"] = FedmsgBlackHole()
# [NBRS] End of the hack


import socket
hostname = socket.gethostname().split('.')[0]

from bodhi.release import VERSION as version

__all__ = ('version', 'hostname')
