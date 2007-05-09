TESTS=test_sdnv.rb test_tcpcl.rb test_logger.rb test_event.rb \
      test_applib.rb test_storage.rb

SOURCES=$(wildcard lib/*.rb)

.PHONY: tests doc

all: tests doc

tests:
	cd test; \
	for t in $(TESTS); do \
	  ruby $$t; \
        done; \
	cd ..


doc:
	rdoc -o doc/source --inline-source $(SOURCES)
