from __future__ import print_function
import sys
import csv
import fileinput

searchReplaceFile = 'old_and_new_paths.csv'
fileToSearch = sys.argv[1]

# read in the search/replace hash
reader = csv.reader(open(searchReplaceFile, 'r'))
replacements = dict(reader)

# iterate over the replacements
for line in fileinput.input(fileToSearch, inplace=True):
    for src, target in replacements.iteritems():
        line = line.replace(src, target)
    print(line, end='')

