
export TESTVERSION=1.0
export TEST=/distribution/rebuild

FILES=runtest.sh $(METADATA)

run:
	./runtest.sh

include /usr/share/rhts/lib/rhts-make.include

$(METADATA):
	@touch $(METADATA)
	@echo "Owner:           Beaker Developers <beaker-devel@lists.fedorahosted.org>" >$(METADATA)
	@echo "Name:            $(TEST)" >>$(METADATA)
	@echo "Path:            $(TEST_DIR)" >>$(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >>$(METADATA)
	@echo "Description:     Rebuilds all distribution packages using mock. For testing mass rebuilds." >>$(METADATA)
	@echo "TestTime:        259200" >>$(METADATA)
	@echo "Priority:        Manual" >>$(METADATA)
	@echo "Requires:        beakerlib" >>$(METADATA)
	@echo "Requires:        mock" >>$(METADATA)
	@echo "Requires:        yum-utils" >>$(METADATA)
	@echo "RhtsOptions:     -Compatible -CompatService" >>$(METADATA)
	@echo "License:         GPLv2+" >>$(METADATA)
