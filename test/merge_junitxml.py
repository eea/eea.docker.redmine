#!/usr/bin/env python

import sys
import xml.etree.ElementTree as ET
import re

def main():
    args = sys.argv[1:]
    if not args:
        merge_results(['TEST-Redmine-Result.xml', 'TEST-Plugins-Result.xml', 'TEST-Result.xml'])
    merge_results(args[:])


def extract_head_from_name(name):
    found = ''
    m = re.search('TEST-(.+?)-Result.xml', name)
    if m:
       found = m.group(1) + '.'
    return found

def merge_results(xml_files):
    tests = 0
    time = 0
    failures = 0
    errors = 0
    skipped = 0
    assertions = 0
    cases = []
    timestamp = ""
    
    for file_name in xml_files[:-2]:
        tree = ET.parse(file_name)
        test_suite = tree.getroot()
        failures += int(test_suite.attrib['failures'])
        tests += int(test_suite.attrib['tests'])
        errors += int(test_suite.attrib['errors'])
        skipped += int(test_suite.attrib['skipped'])
        assertions  += int(test_suite.attrib['assertions'])
        time += float(test_suite.attrib['time'])
        timestamp = test_suite.attrib['timestamp']
        test_name = extract_head_from_name(file_name)

        for testcase in test_suite.iter('testcase'):
            testcase.attrib['name'] = test_name + testcase.attrib['name']   
            cases.append(testcase)

    tree = None

    for file_name in xml_files[-2:]:
        if tree is None:
            tree = ET.parse(file_name)
            test_suite = tree.getroot()
            test_suite.set('failures', str(failures + int(test_suite.attrib['failures'])))
            test_suite.set('tests', str(tests + int(test_suite.attrib['tests'])))
            test_suite.set('errors', str(errors + int(test_suite.attrib['errors'])))
            test_suite.set('skipped', str(skipped + int(test_suite.attrib['skipped'])))
            test_suite.set('assertions', str(assertions  + int(test_suite.attrib['assertions'])))
            test_suite.set('time', str(time + float(test_suite.attrib['time'])))
            test_name = extract_head_from_name(file_name)
            for testcase in test_suite.iter('testcase'):
                testcase.attrib['name'] = test_name + testcase.attrib['name']
            test_suite.extend(cases) 
            #for case in cases:
            #    test_suite.append(case)
                
        else:
            tree.write(file_name, encoding='UTF-8', xml_declaration=True)
    #xml_files[-1:][0])


if __name__ == '__main__':
    main()
