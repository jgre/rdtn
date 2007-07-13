ContactManager
==============

:Author: Janico Greifenberg

The ContactManager is the component in RDTN that tracks the currently available
links and establishes new links or restarts old ones if there are contact
opportunities. It also has the housekeeping function of closing links and
interfaces that are no longer needed or stopped working.

Internal Data Structures
------------------------

The ContactManager maintains two lists: all available links and all available
interfaces. From these lists the ContactManager can determine the convergence
layer type (e.g. ``:tcp``) and for links the opening policy (``:onDemand``,
``:oportunistic``, or ``:alwaysOn``). 

OnDemand links are statically configured, but opened only when the router needs
to forward bundles over this link. AlwaysOn links are statically configured and
opened as soon as possible [2]_. Opportunistic links are created for incoming
connections in connection-oriented convergence layers such as TCP, or they are
created when a discovery mechanism finds an opportunity. 

.. [2] Usually the static configuration of a link is in the config file that is
  read when the daemon starts, so an AlwaysOn link is opened when the daemon reads
  its configuration. But the configuration may also be requested by an application
  interface so that the link is opened when the request is received.

Opportunities
-------------

Finding opportunities is the task of discovery mechanisms such as
Bonjour/Avahi/mDNS or the `Bundle Agent Discovery`_. The implementation of
these mechanisms is described in the internal spec *Discovery*.
When a new opportunity is available, the Discovery module dispatches a
``:opportunityAvailable`` event which the ContactManager subscribes.

An opportunity event contains the following information:

* The convergence layer type (e.g. ``:tcp``, ``:flute``),
* convergence layer specific parameters (e.g. host name and port), and
* optionally the remote EID.

.. _Bundle Agent Discovery: http://www1.tools.ietf.org/html/draft-wyllie-dtnrg-badisc

Events
------

The ContactManager subscribes to the following event through the
EventDispatcher.

``:opportunityAvailable``
  On this event, the ContactManager searches its internal structures for an
  existing link and/or interface, that matches the parameters of the
  opportunity. If an existing one is found that is currently inactive, the
  ContactManager tries to restart it. If no existing link or interface is
  available, a new one is created according to the parameters of the
  opportunity.

``:linkCreated``
  This event causes the ContactManager to insert a new Link object to its
  internal list.

``:linkClosed``
  The closed Link object is removed from the internal list. Later
  implementations may keep the object in a zombie state in order to
  reanimate it later.

``:linkRequired``
  This event is dispatched by a router, when it needs to forward data over a
  link that is configured but not opened. The ContactManager tries to open the
  required link.

Housekeeping
------------

The ContactManager regularly [1]_ queries all links of type ``:onDemand`` and
``:opportunistic`` if they are currently performing a task (sending or
receiving) or if they are idle or in an error state. In the latter cases (idle
or error), the contact manager closes the links.  The interfaces are queried
too, and closed if they are in an error state. The housekeeping functions run in
a separate thread that is started when the ContactManager is initialized.

.. [1] The interval should be a configurable parameter, default: 5 minutes.
