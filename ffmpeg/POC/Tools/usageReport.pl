#!/usr/bin/perl -w
# $Id$

# if no arguments, pring usage
#@ARGV || &usage;

use strict;
use warnings;

use File::Basename;
our $CMDDIRNAME = &dirname($0);

use FindBin qw($Bin);       # where was script installed?

# assumes that this script and the ffmpeg executable are in the 
# same directory
my $searchString = undef;
my $DEBUG = 0;
my $VERBOSE = 0;
my %image2script = ();
my @DIRSTACK = ();

select(STDOUT); $| = 1;     # make unbuffered

#========================================================================
# parse input args
#========================================================================
while (@ARGV) {
    $_ = shift;
    /^-d(ebug)?$/o && do {
	$DEBUG = 1;
	next;
    };
    /^-v(erbose)?$/o && do {
	$VERBOSE = 1;
	next;
    };
    /^-find$/o && do {
	$searchString = shift;
	next;
    };
    /^-h(elp)?$/o && &usage;
    /^-.*$/ && do {
	print "!!! ERROR: $_: Bad option\n";
	exit 1;
    };
}

#========================================================================
# Main loop
#========================================================================

my $dir = '.';


# get all *.config files in current dir on down
opendir (DIR, $dir) or die $!;
while (my $file = readdir(DIR)) {
    $file =~ /\.config$/ || next;
    print "... Processing: ", $file, "\n";

    # parse configfile
    my $imageFile = undef;
    my $audioFile = undef;
    my $lineno = 0;
    my $READ_SCRIPT = 0;

    open (CFGFILE, "$file") || die $!;
    while (my $line = <CFGFILE>) {
	$lineno++;
	# this matches the image entries
	# NOTE: can only process jpg images!
	$line =~ /^((.+?)\.(\w+?))\,(\d{1,2}\:\d{2})\s*$/ && do {
	    $imageFile = $1;
	    # update the hash tables
	    next;
	};
	# this matches the audio file entries
	$line =~ /^((.+?)\.(mp3|wav))\s*$/ && do {
	    $audioFile = $1;
	    next;
	};
	# default: add text to imageFile's script
	if (defined $imageFile) {
	    push @{$image2script{$imageFile}}, $line;
	}
    }
    close CFGFILE;
}
close DIR;

# now look for the search string
for my $imageFile (sort keys %image2script) {
    if ($imageFile =~ /$searchString/) {
	print "### $imageFile:\n";
	for my $line (@{$image2script{$imageFile}}) {
	    print $line;
	}
    }
}

#========================================================================
# Subroutines
#========================================================================

#------------------------------------------------------------------------
sub usage {
#------------------------------------------------------------------------

    print<<"EOF";

USAGE: $0 [options] <config-file>

  Option:                 Description:
  ---------               ----------------------------------------------
  -d(ebug)                # set DEBUG flag
  -h(elp)?                # displays usage
  -v(erbose)              # show more output from ffmpeg

EOF

   exit 1;

} # end: usage

#---------------------------------------------------------------------
sub pushd {
#---------------------------------------------------------------------

    my($dir) = shift;
    my($cwd) = '';

    -d "$dir"
        || die "!!! ERROR: pushd: $dir doesn't exist";

    chop($cwd = `pwd`);
    push(@DIRSTACK, "$cwd");

    chdir "$dir"
        || die "!!! ERROR: pushd: Can't pushd $dir";

    #return the full dir path
    chop($cwd = `pwd`);
    print ">>> Changing dir to $cwd\n";
    return "$cwd";

} # end: pushd

#---------------------------------------------------------------------
sub popd {
#---------------------------------------------------------------------

    @DIRSTACK
        || die "!!! ERROR: popd: Directory stack empty";

    my($dir) = pop(@DIRSTACK);

    -d "$dir"
        || die "!!! ERROR: popd: $dir doesn't exist";
    chdir "$dir"
        || die "!!! ERROR: popd: Can't popd $dir";

    return "$dir";

} # end: popd


