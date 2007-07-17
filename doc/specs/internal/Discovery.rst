DTN Neighbor Discovery
======================

:Author: Janico Greifenberg

Neighbor Discovery has the purpose to detect other bundle routers and announce
the presence of the local bundle router. If another router is found, the
discovery module dispatches an event that allows RDTN to create a link.

The initial version of neighbor discovery in RDTN uses UDP multicast to send and
receive announcements. This is compatible with the `neighbor discovery`_ in the
DTN2 reference implementation.  Later versions will use mDNS service location as
implemented in Bonjour/Avahi.

.. _neighbor discovery: http://www.dtnrg.org/wiki/NeighborDiscovery

Protocol Overview
-----------------

The neighbor discovery module has two parts, the announcer and the receiver. The
announcer part sends beacons for all configured interfaces in regular intervals,
the receiver waits for incoming announcements from other bundle routers. When an
announcement is received, the receiver part dispatches an event.

Announcer and receiver each run in its own thread, the receiver blocks in the
receive function of its socket and the announcer sleeps most of the time and
only wakes up in certain intervals to send out the announcements.

Configuration
-------------

The discovery module can be configure from the RDTN config file with the
following commands:

::

  discovery :address ADDR :port PORT :interval INTERVAL
  discovery :announce INTERFACES

The first command configures the multicast address and the port used by both
announcer an receiver. It also configures the interval between the
announcements.

The second command configures the interfaces that should be announced.
``INTERFACES`` is a list of strings which identify previously configured
interfaces. The names are resolved to ``Interface`` objects using the
``ContactManager#findLink`` method.

Events
------

``:opportunityAvailable``
  When the receiver gets an announcement, it dispatches this event with the
  following parameters:

  ``:type``: The convergence layer type (e.g. ``:tcp``, ``:udp``).
  ``:address``: The address of the remote interface.
  ``:port``: The port of the remote interface.
  ``:eid``: The endpoint identifier of the remote bundle router.

Message Format
--------------

RDTN neighbor discovery uses the message format from the DTN2 reference
implementation (DTN2/servlib/discovery/IPDiscovery.h). 

::

  u_int8_t cl_type;         // Type of CL offered
  u_int8_t interval;        // 100ms units
  u_int16_t length;         // total length of packet
  u_int32_t inet_addr;      // IPv4 address of CL
  u_int16_t inet_port;      // IPv4 port of CL
  u_int16_t name_len;       // length of EID
  char sender_name[0];      // DTN URI of beacon sender
