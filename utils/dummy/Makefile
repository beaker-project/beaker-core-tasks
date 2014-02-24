# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=/distribution

# The name of the package under test:
PACKAGE_NAME=utils

# The path of the test below the package:
RELATIVE_PATH=dummy

# Preserve the RPM name from the old repo location:
export RHTS_RPM_NAME=distribution-distribution-utils-dummy

# Version of the Test. Used with make tag.
export TESTVERSION=1.0

# The compiled namespace of the test.
export TEST=$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)


.PHONY: all install download clean

FILES=	$(METADATA)            \
	runtest.sh             \
	Makefile

run:
	chmod 755 ./runtest.sh
	./runtest.sh

clean:
	rm -f *~ $(BUILT_FILES)

# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

# Generate the testinfo.desc here:
$(METADATA):
	@touch $(METADATA)
	@echo "Owner:           Beaker Developers <beaker-devel@lists.fedorahosted.org>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Description:     Dummy test that does nothing. Used for padding in multihost tests" >> $(METADATA)
	@echo "TestTime:        120" >> $(METADATA)
	@echo "Priority:        Manual" >> $(METADATA)
	@echo "License:         GPLv2+" >> $(METADATA)
