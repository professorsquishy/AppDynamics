#!/usr/bin/perl -w
# $Id$

# if no arguments, pring usage
@ARGV || &usage;

use strict;
use warnings;

use File::Basename;
our $CMDDIRNAME = &dirname($0);

use FindBin qw($Bin);       # where was script installed?

# assumes that this script and the ffmpeg executable are in the 
# same directory
my $CLEANUP = 1;
my $CONFIGFILE = undef;
my $DEBUG = 0;
my $ERR_STATUS = 0;
my $FFMPEG = "$Bin/ffmpeg";
my $FFMPEG_OPTIONS = ' ';
my $IMAGE_TYPE = 'jpg';
my $REPAIR_EOL = 1;
my $REPAIR_EOL_ONLY = 0;
my $VERBOSE = 0;
my $tmpdir = "/tmp/mp4.$$";
my %imageIndex2endTime = ();
my %imageIndex2file = ();
my @CONFIG_ERRORS = ();
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
    /^-example$/o && do {
	&example;
	next;
    };
    /^-v(erbose)?$/o && do {
	$VERBOSE = 1;
	next;
    };
    /^-nocleanup$/o && do {
	$CLEANUP = 0;
	next;
    };
    /^-norepaireol$/o && do {
	$REPAIR_EOL = 0;
	next;
    };
    /^-repaireol$/o && do {
	$REPAIR_EOL_ONLY = 1;
	next;
    };
    /^-h(elp)?$/o && &usage;
    /^-.*$/ && do {
	print "!!! ERROR: $_: Bad option\n";
	exit 1;
    };
    # default: config file
    # make sure they haven't already given you one
    $CONFIGFILE = $_;
}

# make sure you got a CONFIGFILE and that it exists
if (! defined $CONFIGFILE) {
    print "!!! ERROR: CONFIGFILE undefined\n";
    &usage;
} elsif (! -f $CONFIGFILE) {
    print "!!! ERROR: $CONFIGFILE does not exist\n";
    &usage;
}

# determine where the configfile is
my $CONFIGFILEDIR = &dirname($CONFIGFILE);
my $CONFIGFILENAME = &basename($CONFIGFILE);

# now split the config file into name and extension
# use the filename part as the project name
(my $projName = $CONFIGFILENAME) =~ s/\..+$//;

#========================================================================
# Main loop
#========================================================================

# pushd into the CONFIGFILE dir
$CONFIGFILEDIR = &pushd($CONFIGFILEDIR);

# if the $REPAIR_EOL_ONLY flag is set, just do that
if ($REPAIR_EOL_ONLY) {
    &fixEolChars($CONFIGFILE);
    exit 0;
}

# parse configfile
my $errString = '';
my $index = '01';
my $lineno = 0;
my $numOfImageFiles = 0;
my $numOfImageLines = 0;
my ($audioFile, $audioType) = undef;
my ($imageFile, $imageType, $endTime) = undef;

open (CFG, "$CONFIGFILENAME") || die $!;
while (<CFG>) {
    $lineno++;
    # keep count of jpg entries
    /\.$IMAGE_TYPE,/ && do {
	$numOfImageLines++;
    };
    # ignore comments and blank lines
    /^#/ && next;
    /^\s+$/ && next;
    # this matches the image entries
    # NOTE: can only process jpg images!
    /^((.+?)\.(\w+?))\,(\d{1,2}\:\d{2})\s*$/ && do {
	($imageFile, $imageType, $endTime) = ($1, $3, $4);
	# make sure it's a jpg image
	if ($imageType ne $IMAGE_TYPE) {
	    $errString = "!!! Line #" . $lineno . ": Unsupported image type: " . $imageType . "\n>>> " . $_;
	    push @CONFIG_ERRORS, $errString;
	    next;
	}
	# update numOfImageFiles
	$numOfImageFiles++;
	# update the hash tables
	$imageIndex2file{$index} = $imageFile;
	$imageIndex2endTime{$index} = $endTime;
	# increment the index
	$index++;
	next;
    };
    # this matches the audio file entries
    /^((.+?)\.(mp3|wav))\s*$/ && do {
	($audioFile, $audioType) = ($1, $2);
	next;
    };
    # catch all:
    # if we get here, there's some sort of syntax error
    $errString = "!!! Line #" . $lineno . ": Unrecognized line\n>>> " . $_;
    push @CONFIG_ERRORS, $errString;
}
close CFG;

# first, test if there are any errors in the config file syntax
if (@CONFIG_ERRORS) {
    print "!!! ERROR: the following lines in the config file have errors:\n";
    for my $err (@CONFIG_ERRORS) {
	print $err;
    }
    exit 1;
}

# make sure image files are defined and exist
if (! defined $imageIndex2file{'01'}) {
    print "!!! ERROR: no image files defined!\n";
    $ERR_STATUS = 1;
} else {
    for my $key (sort keys %imageIndex2file) {
	if (! -f $imageIndex2file{$key}) {
	    print "!!! ERROR: image file does not exist:\n";
	    print ">>> ", $imageIndex2file{$key}, "\n";
	    $ERR_STATUS = 1;
	}
    }
}

# make sure the number of jpg entries matches the num of image files
# this should catch the MS EOL issues
if ($numOfImageFiles != $numOfImageLines) {
    print "!!! WARNING: numOfImageFiles (", $numOfImageFiles, ') != numOfImageLines (', $numOfImageLines, ")\n";
    print "!!! Could be DOS EOL issues in your config file\n";
    # only repair if $REPAIR_EOL is set
    if ($REPAIR_EOL) {
	&fixEolChars($CONFIGFILE);
	$ERR_STATUS = 1;
    }
}

# make sure the audio file is defined and exists
if (! defined $audioFile) {
    print "!!! ERROR: audioFile undefined\n";
    $ERR_STATUS = 1;
} elsif (! -f $audioFile) {
    print "!!! ERROR: audio file does not exist\n";
    print ">>> ", $audioFile, "\n";
    $ERR_STATUS = 1;
}

# if ERR_STATUS has been set, exit
if ($ERR_STATUS) {
    exit 1;
}

######################################################################
# if we get this far, we have verified the contents of the config file
# :-)
######################################################################

# create tmp dir with timestamped image files
mkdir $tmpdir unless $DEBUG;
# make the initial timestamp 01/01/2000 GMT
my $startTime = 946684800;
my $imageEndTime = undef;
my $touchDate = &epochTime2date($startTime);
my $outfile = '00' . '.' . $imageType;

# make the initial 00 image from the first image
print "... Generating screenshot sequence:\n";
print ">>> cp $imageIndex2file{'01'} $tmpdir/$outfile\n";
system "cp $imageIndex2file{'01'} $tmpdir/$outfile" unless $DEBUG;
print ">>> touch -t $touchDate $tmpdir/$outfile\n";
system "touch -t $touchDate $tmpdir/$outfile" unless $DEBUG;

# now process the rest of the image files
for my $key (sort keys %imageIndex2file) {
    $outfile = $key . '.' . $imageType;
    $imageEndTime = &endTime2seconds($imageIndex2endTime{$key}) + $startTime;
    $touchDate = &epochTime2date($imageEndTime);
    print ">>> cp $imageIndex2file{$key} $tmpdir/$outfile\n";
    system "cp $imageIndex2file{$key} $tmpdir/$outfile" unless $DEBUG;
    print ">>> touch -t $touchDate $tmpdir/$outfile\n";
    system "touch -t $touchDate $tmpdir/$outfile" unless $DEBUG;
}
# copy the audio file to the tmpdir
print "... Copying audio file:\n";
print ">>> cp $audioFile $tmpdir\n";
system "cp $audioFile $tmpdir";
# need this for the ffmpeg command later
my $audioFileName = &basename($audioFile);

# pushd into the tmpdir
&pushd($tmpdir) unless $DEBUG;

# NOTE: can only process jpg images!!
my $ffmpegCmd = "$FFMPEG -ts_from_file 1 -i %2d.jpg -i $audioFileName -c:v libx264 $projName.mp4"; 

print "... Executing ffmpeg:\n";
print ">>> $ffmpegCmd\n";
#system "$FFMPEG -ts_from_file 1 -i %2d.png -i $audioFileName -c:v libx264 $projName.mp4" unless $DEBUG;
if (! $DEBUG) {
    open(FFMPEG, "$ffmpegCmd 2>&1 |") || die $!;
    while (<FFMPEG>) {
	print if $VERBOSE;
    }
    close FFMPEG;

    # make sure a video file was produced
    if (! -f "$tmpdir/$projName.mp4") {
	print "!!! ERROR: $projName.mp4 was not created\n";
	print "!!! ERROR: Run with -verbose option for details\n";
	# cleanup end exit with stat = 1
	&cleanUp(1);
    } else {
	# mv the mp4 file back to the dir where the config file lives
	print "... Moving $projName.mp4 to $CONFIGFILEDIR\n";
	system ("mv $projName.mp4 $CONFIGFILEDIR") unless $DEBUG;
	print "... Done\n";
    }
}

# cleanup end exit with stat = 0
$CLEANUP && &cleanUp(0);

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
  -example                # show config file example
  -h(elp)?                # displays usage
  -repaireol              # just repair the EOL char issue
  -norepaireol            # skip repairin the EOL char issue
  -v(erbose)              # show more output from ffmpeg

EOF

   exit 1;

} # end: usage

#------------------------------------------------------------------------
sub example {
#------------------------------------------------------------------------

    print<<"EOF";


Config file lines must be one of the following:

Comments:
--------

"#" at the beginning of the line

Image File: (jpg files only!!!)
----------

<path-to-image-file>,<end-time-in-MM:SS>

e.g.:

../Screenshots-jpg/01-application_dashboard/Intro_APM_demo10.jpg,05:36

Audio File: (mp3 or wav files)
----------

<path-to-audio-file>

e.g.:

../Audio/Intro_to_APM.mp3

EOF

   exit 1;

} # end: usage

#------------------------------------------------------------------------
sub cleanUp {
#------------------------------------------------------------------------

    my $exitStat = shift;
    # rm tmpdir
    system "rm", "-rf", $tmpdir;
    &popd;
    exit $exitStat;

}

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

#------------------------------------------------------------------------
sub endTime2seconds {
#------------------------------------------------------------------------

    # converts MM:SS to seconds

    my $time = shift;

    my ($min, $sec) = split ':', $time;

    return ($min * 60) + $sec;

} # end: endTime2seconds

#------------------------------------------------------------------------
sub epochTime2date {
#------------------------------------------------------------------------

    # converts epoch time to real time

    my $time = shift;

    my ($sec,$min,$hour,$day,$month,$year) = (gmtime($time))[0,1,2,3,4,5,6]; 

    # add one to month index
    $month++;

    # pad values with 0's if required
    for my $val (\$sec, \$min, \$hour, \$day, \$month) {
	while(length($$val)<2) {
	    $$val = "0" . $$val;
	}
    }


    my $date = $month.$day.$hour.$min.".".$sec;

    return $date;

} # end: epochTime2date

#------------------------------------------------------------------------
sub fixEolChars {
#------------------------------------------------------------------------

    # this function will run perl over the file in an attempt to
    # fix it
    my $file = shift;
    my $bakFile = $file . '.bak';

    # need to replace stray \r chars anywhere in the line
    my $regex = 's@\r@\n@g';

    if (! -f $file) {
	print "!!! ERROR: $file does not exist\n";
	exit 1;
    }

    my $cmd = 'perl -pi.bak -e "' . $regex . '" ' . $file;

    # munge the file and save orig into .bak
    print "### Repairing config file (saving original file in: ", $bakFile, ")\n";
    system ($cmd);
    
    # diff the files
    print "### Diffing: ", $file, ' and ', $bakFile, "\n";
    system ("diff", $file, $bakFile);

}
