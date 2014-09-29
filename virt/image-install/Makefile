# The toplevel namespace within which the test lives.
TOPLEVEL_NAMESPACE=/distribution

# The name of the package under test:
PACKAGE_NAME=virt

# The path of the test below the package:
RELATIVE_PATH=image-install

# Version of the Test. Used with make tag.
export TESTVERSION=1.0

# The compiled namespace of the test.
export TEST=$(TOPLEVEL_NAMESPACE)/$(PACKAGE_NAME)/$(RELATIVE_PATH)

# Define to copy files
define cpfile
	echo "Chmod a+x $(1)" ; \
	chmod a+x ./$(1) ; \
	echo "Copying $(1)" ; \
	cp ./$(1) /usr/local/bin/. ; \
	echo "Restore SELinux context $(1)" ; \
	restorecon -vv /usr/local/bin/$(1) ;
endef

BINFILES= guestcheck4down   \
	guestcheck4up     \
	guestgethostname  \
	startguest        \
	stopguest         \
	virshstartguest   \
	virshstopguest    \
	wait4shutdown     \
	wait4login        \
	wait4guest        \
	xmstopguest       \
	xmstartguest      \
	getguestnames.sh  \
	isparavirt        \
	ishvm             \
	isxen             \
	iskvm             \
	isptyconsole      \
	isfileconsole     \
	filetopty.sh      \
	ptytofile.sh      \
	getconsolefile    \
	get_guest_info.py \
	get_guest_fqdn.py \
	rhts_submit_virt_logs \
	rhts_virt_funcs.sh    \
	guest1cmd             \
	scp.exp               \
	zrhel5_write_consolelogs.py \
	lxml_guestname_resolution.py \
	minidom_guestname_resolution.py \
	wait4guesttasks

FILES=	$(METADATA)       \
	$(BINFILES)       \
	runtest.sh        \
	Makefile          \
	virtinstall.exp   \
	get_guest_info.py \
	get_guest_fqdn.py \
	get_user_data.py  \
	start_recipe.py   \
	logguestconsoles.c \
	logguestconsoles.initd \
	zrhel5_write_consolelogs.initd \
	iptables_after_libvirtd.initd

binsetup:
	$(foreach f,$(BINFILES),$(call cpfile,$(f)))

run: binsetup
	chmod a+x ./runtest.sh ./*.exp ./*.py 
	./runtest.sh

# Include Common Makefile
include /usr/share/rhts/lib/rhts-make.include

# Generate the testinfo.desc here:
$(METADATA):
	@touch $(METADATA)
	@echo "Owner:           Beaker Developers <beaker-devel@lists.fedorahosted.org>" > $(METADATA)
	@echo "Name:		$(TEST)"	>> $(METADATA)
	@echo "Path:		$(TEST_DIR)"	>> $(METADATA)
	@echo "TestVersion:	$(TESTVERSION)"	>> $(METADATA)
	@echo "Description:	Test to install KVM guests from a cloud image" >> $(METADATA)
	@echo "TestTime:	43200"		>> $(METADATA)
	@echo "Requires:	$(PACKAGE_NAME)"  >> $(METADATA)
	@echo "Architectures:	i386 x86_64 ia64" >> $(METADATA)
	@echo "Priority:	Manual" >> $(METADATA)
	@echo "Requires:	autofs" >> $(METADATA)
	@echo "Requires:	bridge-utils" >> $(METADATA)
	@echo "Requires:	expect" >> $(METADATA)
	@echo "Requires:	genisoimage" >> $(METADATA)
	@echo "Requires:	kvm"            >> $(METADATA)
	@echo "Requires:	libvirt" >> $(METADATA)
	@echo "Requires:	mkisofs" >> $(METADATA)
	@echo "Requires:	openssh-server" >> $(METADATA)
	@echo "Requires:	python-virtinst" >> $(METADATA)
	@echo "Requires:	virt-manager" >> $(METADATA)
	@echo "Requires:	virt-viewer" >> $(METADATA)
	@echo "Requires:	vnc" >> $(METADATA)
	@echo "Requires:	vnc-server" >> $(METADATA)
	@echo "Requires:	xorg-x11-server-Xvfb" >> $(METADATA)
	@echo "Requires:	xmlrpc-c-devel" >> $(METADATA)
	@echo "Requires:	openssl-devel"  >> $(METADATA)
	@echo "Requires:	libcurl-devel"  >> $(METADATA)
	@echo "Requires:	libxml2-devel"  >> $(METADATA)
	@echo "Requires:	pykickstart"  >> $(METADATA)
	@echo "Requires:	@virtualization" >> $(METADATA)
	@echo "Requires:	@virtualization-platform" >> $(METADATA)
	@echo "Requires:	@virtualization-tools" >> $(METADATA)
	@echo "Requires:	@virtualization-client" >> $(METADATA)
	@echo "Requires:	@x11" >> $(METADATA)
	@echo "Requires:	@fonts" >> $(METADATA)
	@echo "RhtsOptions:     -Compatible -CompatService" >> $(METADATA)
	@echo "License:		GPLv2"		>> $(METADATA)
