#!/usr/bin/python

import os
import sys
import xmlrpclib
import xml.dom.minidom
import time

xml_tries = 1
interval = 300
proxy = xmlrpclib.ServerProxy('http://%s:8000/RPC2' % os.environ['LAB_CONTROLLER'])
while xml_tries < 5:
    try:
        recipe_xml = proxy.get_my_recipe(dict(recipe_id=os.environ['RECIPEID']))
        break
    except:
        sys.stderr.write("Couldn't get guestinfo from %s . sleeping %i secs\n" % (os.environ['LAB_CONTROLLER'], interval))
        time.sleep(interval)
        xml_tries += 1

if xml_tries == 5:
    sys.stderr.write("Can't get guestinfo from %s\n" % os.environ['LAB_CONTROLLER'])
    sys.exit(1)


doc = xml.dom.minidom.parseString(recipe_xml)

if len(sys.argv) >= 2 and sys.argv[1] == '--kvm-num': # this is kind of a hack...
    num = len(doc.getElementsByTagName('guestrecipe'))
    kvm_num = len([guestrecipe for guestrecipe in doc.getElementsByTagName('guestrecipe')
            if '--kvm' in guestrecipe.getAttribute('guestargs')])
    if kvm_num and kvm_num < num:
        sys.exit(2)
    print kvm_num
    sys.exit(0)

for guestrecipe in doc.getElementsByTagName('guestrecipe'):
    print ' '.join([
        guestrecipe.getAttribute('id') or 'RECIPEIDMISSING',
        guestrecipe.getAttribute('guestname')
            or 'guestrecipe%s' % guestrecipe.getAttribute('id'),
        guestrecipe.getAttribute('mac_address') or 'RANDOM',
        guestrecipe.getAttribute('location') or 'LOCATIONMISSING',
        guestrecipe.getAttribute('kickstart_url') or 'KSMISSING',
        guestrecipe.getAttribute('guestargs'),
    ])
