# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=/distribution

# The name of the package under test:
PACKAGE_NAME=virt

# The path of the test below the package:
RELATIVE_PATH=start_stop

# Version of the Test. Used with make tag.
export TESTVERSION=2.1

# The compiled namespace of the test.
export TEST=$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)

.PHONY: all install download clean

FILES=	$(METADATA)            \
	runtest.sh             \
	Makefile               

run:
	chmod a+x ./runtest.sh
	./runtest.sh

clean:
	rm -f *~ $(BUILT_FILES)
	rm -f rh-tests-xen-install*

# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

# Generate the testinfo.desc here:
$(METADATA):
	@touch $(METADATA)
	@echo "Owner:		Kernel QE team <kernelqe@redhat.com>" > $(METADATA)
	@echo "Name:		$(TEST)"	>> $(METADATA)
	@echo "Path:		$(TEST_DIR)"	>> $(METADATA)
	@echo "TestVersion:	$(TESTVERSION)"	>> $(METADATA)
	@echo "Description:	Start and stop virtual machines" >> $(METADATA)
	@echo "TestTime:	7200"		>> $(METADATA)
	@echo "Architectures:	i386 x86_64 ia64" >> $(METADATA)
	@echo "Priority:	Manual"		>> $(METADATA)
	@echo "License:		GPLv2" >> $(METADATA)
