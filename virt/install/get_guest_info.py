#!/usr/bin/python2

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

import optparse
import os
import shlex
import sys
import time
import xml.dom.minidom
import xmlrpclib


def get_recipe():
    recipe_xml = None
    interval = 300
    proxy = xmlrpclib.ServerProxy('http://%s:8000/RPC2' % os.environ['LAB_CONTROLLER'])

    for _ in range(5):
        try:
            recipe_xml = proxy.get_my_recipe(dict(recipe_id=os.environ['RECIPEID']))
            break
        except:
            sys.stderr.write("Couldn't get guestinfo from %s . sleeping %i secs\n" % (
                os.environ['LAB_CONTROLLER'], interval))
            time.sleep(interval)

    if not recipe_xml:
        sys.stderr.write("Can't get guestinfo from %s\n" % os.environ['LAB_CONTROLLER'])
        sys.exit(1)

    return recipe_xml


def parse_args():
    parser = optparse.OptionParser()
    parser.add_option('--kvm-num', action='store_true', dest='kvm', default=False,
                      help='Validate guest recipe.')
    parser.add_option('--location', dest='location', choices=['nfs', 'http', 'ftp'], default='nfs')

    (options, _) = parser.parse_args()

    return options.kvm, options.location


def validate(guest_doc):
    num = len(guest_doc)
    kvm_num = len([guestrecipe for guestrecipe in guest_doc
                   if '--kvm' in guestrecipe.getAttribute('guestargs')])

    if kvm_num and kvm_num < num:
        # User mixed up KVM and XEN
        sys.exit(2)

    print(kvm_num)
    sys.exit(0)


if __name__ == '__main__':
    VALIDATION, location = parse_args()
    GUEST_RECIPE_DOC = xml.dom.minidom.parseString(get_recipe()).getElementsByTagName('guestrecipe')

    if VALIDATION:
        validate(GUEST_RECIPE_DOC)

    location += '_location'
    for guestrecipe in GUEST_RECIPE_DOC:
        guest_location = location
        if filter(lambda meta: 'method' in meta, shlex.split(guestrecipe.getAttribute('ks_meta'))):
            # Let user to use method defined by guest recipe
            guest_location = 'location'
        print('\t'.join([
            guestrecipe.getAttribute('id') or 'RECIPEIDMISSING',
            guestrecipe.getAttribute('guestname')
            or 'guestrecipe%s' % guestrecipe.getAttribute('id'),
            guestrecipe.getAttribute('mac_address') or 'RANDOM',
            guestrecipe.getAttribute('%s' % guest_location) or 'LOCATIONMISSING',
            guestrecipe.getAttribute('kickstart_url') or 'KSMISSING',
            guestrecipe.getAttribute('guestargs'),
            guestrecipe.getAttribute('kernel_options'),
        ]))
