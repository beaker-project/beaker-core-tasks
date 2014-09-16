#!/usr/bin/python

import os
import sys
from optparse import OptionParser
from pykickstart.parser import KickstartParser
from pykickstart.version import makeVersion
from pykickstart.errors import KickstartError


__version__ = '0.1'
__description__ = 'Generate cloud-init user-data by given kickstart'

def get_parser():
    usage = "usage: %prog [options]"
    parser = OptionParser(usage, description=__description__,version=__version__)
    parser.add_option("-k", "--kickstart-file", dest="ksfile", metavar="FILE")
    return parser

def process_kickstart(ksfile):
    # pykickstart refs
    # https://jlaska.fedorapeople.org/pykickstart-doc/pykickstart.commands.html
    ksparser = KickstartParser(makeVersion())
    try:
        ksparser.readKickstart(ksfile)
    except KickstartError as e:
        sys.stderr.write(str(e))
        sys.exit(1)
    user_data = '#!/bin/bash'
    # repo
    for repo in ksparser.handler.repo.repoList:
        if repo.mirrorlist:
            repo_url = 'metalink=%s' % repo.mirrorlist
        else:
            repo_url = 'baseurl=%s' % repo.baseurl
        user_data += """
cat <<"EOF" >/etc/yum.repos.d/%s.repo
[%s]
name=%s
%s
enabled=1
gpgcheck=0
EOF
""" % (repo.name,
       repo.name,
       repo.name,
       repo_url)  
    # rootpw
    if ksparser.handler.rootpw.isCrypted:
        user_data += 'echo "root:%s" | chpasswd -e\n' % ksparser.handler.rootpw.password
    else:
        user_data += 'echo "root:%s" | chpasswd\n' % ksparser.handler.rootpw.password
    # selinux
    if ksparser.handler.selinux.selinux is 0:
        selinux_status = 'disabled'
    elif ksparser.handler.selinux.selinux is 2:
        selinux_status = 'enforcing'
    else:
        selinux_status = 'enforcing'
    user_data += "sed -i 's/SELINUX=.*/SELINUX=%s/' /etc/selinux/config\n" % selinux_status
    # %packages
    packages = []
    for group in ksparser.handler.packages.groupList:
        packages.append("@%s" % group.name)
    for package in ksparser.handler.packages.packageList:
        packages.append(package)
    if packages:
        user_data += "yum -y install %s\n" % ' '.join(packages)
    # skip %prep
    # %post
    user_data += ksparser.handler.scripts[1].script
    # remove cloud-init package and reboot
    user_data += 'yum -y remove cloud-init\nreboot'
    print user_data

def main(*args):
    parser = get_parser()
    (options, args) = parser.parse_args(*args)
    ksfile = options.ksfile
    if ksfile is None:
        parser.error('Missing kickstart')
    process_kickstart(ksfile)
    return

if __name__ == '__main__':
    main()
