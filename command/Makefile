# The toplevel namespace within which the test lives.
PACKAGE_NAME=distribution

# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=/$(PACKAGE_NAME)

# The version of the test rpm that gets
#  created / submitted
export TESTVERSION=1.1

# The path of the test below the package
RELATIVE_PATH=command

# Preserve the RPM name from the old repo location:
export RHTS_RPM_NAME=distribution-distribution-command

# The relative path name to the test
export TEST=$(TOPLEVEL_NAMESPACE)/$(RELATIVE_PATH)

# A phony target is one that is not really the name of a file.
#  It is just a name for some commands to be executed when you
#  make an explicit request. There are two reasons to use a
#  phony target: to avoid a conflict with a file of the same
#  name, and to improve performance.
.PHONY: all install clean

# data files, .c files, scripts anything needed to either compile the test and/or run it.
FILES=$(METADATA) runtest.sh PURPOSE

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	chmod a+x runtest.sh

clean:
	rm -f *~ testinfo.desc $(BUILT_FILES)

# Include a global make rules file
include /usr/share/rhts/lib/rhts-make.include

# Generate the testinfo.desc here:
$(METADATA): Makefile
	@touch $(METADATA)
	@echo "Name:		$(TEST)"	> $(METADATA)
	@echo "Description:	Execute any arbitrary command." >> $(METADATA)
	@echo "Path:		$(TEST_DIR)"	>> $(METADATA)
	@echo "TestTime:	180m"		>> $(METADATA)
	@echo "TestVersion:	$(TESTVERSION)"	>> $(METADATA)
	@echo "License:		GPL"		>> $(METADATA)
	@echo "Owner:           Beaker Developers <beaker-devel@lists.fedorahosted.org>" >>$(METADATA)
