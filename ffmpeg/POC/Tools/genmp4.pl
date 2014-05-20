#!/usr/bin/perl -w

@ARGV || &usage;

use strict;
use warnings;

use File::Basename;
our $CMDDIRNAME = &dirname($0);

use FindBin qw($Bin);       # where was script installed?

# assumes that this script and the ffmpeg executable are in the 
# same directory
my @DIRSTACK = ();
my $FFMPEG = "$Bin/ffmpeg";
my $FFMPEG_OPTIONS = ' ';
my $DEBUG = 0;
my $CONFIGFILE = undef;
my %imageIndex2file = ();
my %imageIndex2duration = ();
my $tmpdir = "/tmp/mp4.$$";

select(STDOUT); $| = 1;     # make unbuffered

#========================================================================
# parse input args
#========================================================================
while (@ARGV) {
    $_ = shift;
    /^-d(ebug)?$/o && do {
	# set log level to DEBUG
	$DEBUG = 1;
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
(my $projName = $CONFIGFILE) =~ s/\..+$//;

#========================================================================
# Main loop
#========================================================================

# pushd into the CONFIGFILE dir
$CONFIGFILEDIR = &pushd($CONFIGFILEDIR);

# parse configfile
my $index = '01';
my ($imageFile, $imageType, $duration) = undef;
my ($audioFile, $audioType) = undef;

open (CFG, "$CONFIGFILENAME") || die $!;
while (<CFG>) {
    # ignore comments and blank lines
    /^#/ && next;
    /^\s+$/ && next;
    /^((.+?)\.(png|jpg))\,(.+)/ && do {
	($imageFile, $imageType, $duration) = ($1, $3, $4);
	# update the hash tables
	$imageIndex2file{$index} = $imageFile;
	# pad duration
	while(length($duration)<2) {
	    $duration = "0" . $duration;
	}

	$imageIndex2duration{$index} = $duration;
	# increment the index
	$index++;
	next;
    };
    /^((.+?)\.(wav))$/ && do {
	($audioFile, $audioType) = ($1, $2);
	next;
    };
    # catch all, some sort of syntax error
    print "!!! ERROR: config file line unrecognized:\n";
    print ">>> $_";
    exit 1;
}
close CFG;

# make sure image files are defined and exist
if (! defined $imageIndex2file{'01'}) {
    print "!!! ERROR: no image files defined!\n";
    exit 1;
} else {
    for my $key (sort keys %imageIndex2file) {
	if (! -f $imageIndex2file{$key}) {
	    print "!!! ERROR: image file does not exist:\n";
	    print ">>> $imageIndex2file{$key}";
	    exit 1;
	}
    }
}
# make sure the audio file is defined and exists
if (! defined $audioFile) {
    print "!!! ERROR: audioFile undefined\n";
    exit 1;
} elsif (! -f $audioFile) {
    print "!!! ERROR: $audioFile does not exist\n";
    print ">>> $audioFile";
    exit 1;
}

# if we get this far, we have verified the contents of the config file
# :-)

# create tmp dir with timestamped image files
mkdir $tmpdir unless $DEBUG;
# make the initial 00 image from the first image
my $touchTime = 946684800;
my $outfile = '00' . '.' . $imageType;

print "cp $imageIndex2file{'01'} $tmpdir/$outfile\n";
system "cp $imageIndex2file{'01'} $tmpdir/$outfile" unless $DEBUG;
print "touch -a $touchTime $tmpdir/$outfile\n";
system "touch -a $touchTime $tmpdir/$outfile" unless $DEBUG;

# now process the rest of the image files
for my $key (sort keys %imageIndex2file) {
    $outfile = $key . '.' . $imageType;
    $touchTime += $imageIndex2duration{$key};
    print "cp $imageIndex2file{$key} $tmpdir/$outfile\n";
    system "cp $imageIndex2file{$key} $tmpdir/$outfile" unless $DEBUG;
    print "touch -a $touchTime $tmpdir/$outfile\n";
    system "touch -a $touchTime $tmpdir/$outfile" unless $DEBUG;
}
# copy the audio file to the tmpdir
print "cp $audioFile $tmpdir\n";
system "cp $audioFile $tmpdir";
# need this for the ffmpeg command later
my $audioFileName = &basename($audioFile);

# pushd into the tmpdir
&pushd($tmpdir) unless $DEBUG;

# run ffmpeg using the tmpdir files we created above
system "$FFMPEG -ts_from_file 1 -i %d2.png -i $audioFileName -c:v libx264 $projName.mp4" unless $DEBUG;

# mv the mp4 file back
system ("mv $projName.mp4 $CONFIGFILEDIR") unless $DEBUG;

# go back to original dir
&popd unless $DEBUG;

# cleanup end exit
&cleanUp;

exit 0;

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
  -d(ebug)                # set global DEBUG flag
  -h(elp)?                # displays usage

EOF

   exit 1;

} # end: usage


#------------------------------------------------------------------------
sub cleanUp {
#------------------------------------------------------------------------

    system "rm", "-rf", $tmpdir;
    &popd;

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

    chop($cwd = `pwd`);
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
