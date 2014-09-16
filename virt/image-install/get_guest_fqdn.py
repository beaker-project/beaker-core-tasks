#!/usr/bin/python

import os
import sys
import xmlrpclib
import xml.dom.minidom
import time

if len(sys.argv) is not 2:
	print "Usage: %s RECIPEID" % __file__
	sys.exit(1)
recipeid = sys.argv[1]
try:
	int(recipeid)
except:
	print "RECIPEID must be an integer"
	sys.exit(1)

xml_tries = 1
interval = 300
proxy = xmlrpclib.ServerProxy('http://%s:8000/RPC2' % os.environ['LAB_CONTROLLER'])
while xml_tries < 5:
	try: 
		recipe_xml = proxy.get_my_recipe(dict(recipe_id=recipeid))
		break
	except:
		print "Couldn't get guestinfo from %s . sleeping %i secs" % (os.environ['LAB_CONTROLLER'] , interval)
		time.sleep(interval)
		xml_tries += 1

if xml_tries == 5:
	print "Can't get guestinfo from %s" % os.environ['LAB_CONTROLLER']
	sys.exit(1)


doc = xml.dom.minidom.parseString(recipe_xml)

for guestrecipe in doc.getElementsByTagName('guestrecipe'):
    print guestrecipe.getAttribute('system')
