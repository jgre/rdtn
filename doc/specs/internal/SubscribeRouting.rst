Subscribe-based Routing
=======================

:Author: Janico Greifenberg

Subscribe bundles are sent to ``[Sender-EID]/subscribe``.

Packet Format
-------------

EID length: SDNV
EID: String
Expiry date: SDNV, number of seconds since 01-01-2000
Hops from original subscriber: SDNV
Subscription Creation time: SDNV, number of seconds since 01-01-2000
Bundles seen: List of (length (SDNV), Bundle-URI (string)) pairs.

Example Run
-----------

R2 subscribes to EID1 from S1.
R3 subscribes to EID2 from S2.

Internal Scores (Global, Sender S1, Sender S2, EID1, EID2):
All: (0.5, 0.5, 0.5, 0.5, 0.5)

R2 subscribes:
R2: (0.5, 0.75, 0.5, 1, 0.5)
R2 -> I2 (Hop count 1)
I2: (0.5, 0.6, 0.5, 0.75, 0.5)
I2 -> R1 (Hop count 2)
R1: (0.5, 0.57, 0.5, 0.7, 0.5)
R1 -> K1 (Hop count 3)
R1 -> I1 (Hop count 3)
K1, I1: (0.5, 0.55, 0.5, 0.65, 0.5)
K1 -> M (Hop count 4)
K1 -> I3 (Hop count 4)
M, I3: (0.5, 0.53, 0.5, 0.6, 0.5)
M -> K2 (Hop count 5)
K2: (0.5, 0.52, 0.5, 0.57, 0.5)
M -> C (Hop count 5)
C: (0.5, 0.52, 0.5, 0.57, 0.5)

S1 sends a bundle:
S1 -> C -> M
C: (0.55, 0.57, 0.5, 0.6, 0.5)
M: (0.53, 0.57, 0.5, 0.62, 0.5)
M -> K1
M: (0.55, 0.6, 0.5, 0.65, 0.5)
K1: (0.53, 0.57, 0.5, 0.67, 0.5)
K1 -> R2
K1 -> I3
K1: (0.55, 0.6, 0.5, 0.7, 0.5)
R1: (0.53, 0.6, 0.5, 0.73, 0.5)


