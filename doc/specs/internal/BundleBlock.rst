Separation of Bundle Blocks into Separate Objects
=================================================

:Author: Janico Greifenberg

A Bundle comprises a number of blocks, at least the primary bundle block and the
payload block. The number of optional extension blocks (e.g. encryption blocks)
is unlimited. To be able to deal with the different formats and semantics of
bundle blocks, the RDTN implementation needs to represent the bundle blocks in
different classes. The separation makes it possible to keep only some blocks in
RAM, while storing others (namely the payload) only on disk.

Bundle Classes
--------------

The main interface class for all blocks is ``Bundle``. This class provides a
direct interface to the fields of the primary bundle block (e.g. destination
EID, creation timestamp, etc.) and gives access to the payload. The ``Bundle``
class is also responsible for parsing, serialization, fragmentation, and
reassembly.

Internally ``Bundle`` has a list of objects representing the blocks in the
bundle. The list of blocks is public. The accessor methods of ``Bundle`` are
mapped to the corresponding accessors of the block object. E.g., the method
``Bundle#destEid`` is mapped to the ``destEid`` method of the object
representing the primary bundle block.

Each bundle block class must define a ``to_s`` method that serializes the block
in the appropriate format. The following classes are implemented initially:

PrimaryBundleBlock
  The PrimaryBundleBlock class encapsulates the information that is present in
  every bundle. This class takes most of the fields from the previous monolithic
  design of the Bundle class.
Class PayloadBlock
  Objects of this class store the payload either directly in memory as a string
  or they hold the path of a file where the payload is stored and can be read on
  demand.
