#!/usr/bin/python
#
# this script is used to update the /etc/hosts file in the host/dom0 so that the
# guestname will be resolved to the guest's IP address. 
#

import sys
import os
import time
import xmlrpclib
import xml.dom.minidom
from cStringIO import StringIO
from optparse import OptionParser
import socket

#start here
usage = "usage: %prog --recipeid "
parser = OptionParser()
parser.add_option("-r", "--recipeid", dest="recipeid", help="recipe id of the guest to hostname of.")
(options, args) = parser.parse_args()
recipeid = options.recipeid

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

dom = xml.dom.minidom.parseString(recipe_xml)
for el in dom.getElementsByTagName('guestrecipe'):
	mydict = dict(el.attributes.items())
	for key in mydict:
		if key == 'id' and mydict[key] == recipeid:
			guestname = mydict['guestname']
			guesthost = mydict['system']
			guestip = socket.gethostbyname(guesthost)
			print "guestname: " + guestname + " guesthost: " + guesthost + " ip: " + guestip
			# update /etc/hosts with this info
			fh = open('/etc/hosts', 'a')
			fh.write(guestip+"      "+guestname+"\n")
			fh.close()
sys.exit(0)


