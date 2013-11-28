#!/usr/bin/python

"""
Marks a guest recipe as started. Pass the recipe ID as the first argument.
"""

import os
import sys
import xmlrpclib
import xml.dom.minidom

proxy = xmlrpclib.ServerProxy('http://%s:8000/RPC2' % os.environ['LAB_CONTROLLER'])
recipe_id = int(sys.argv[1])
recipe_xml = proxy.get_my_recipe(dict(recipe_id=recipe_id))
doc = xml.dom.minidom.parseString(recipe_xml)

# This is the same logic as when the 'reboot' command goes through for a real 
# system... grab the first task in the recipe and mark it as started. This will 
# set the state of the recipe to Running and start the watchdog with some time 
# on the clock. The watchdog will be extended again once Anaconda hits 
# install_start.
first_task = doc.getElementsByTagName('task')[0]
proxy.task_start(first_task.getAttribute('id'))
