#!perl -T
use Test::More tests => 2 + 1 + 1 + 1 + 1;
use Term::TtyRec::Plus;

# "constants"
my $ttyrec = "t/nethack.ttyrec";
my $frames = 1783;
my $time = 434.991698026657;
my $time_truncated = 35.601359128952;
my $time2 = 2.890479;

# check whether two floating point values are close enough
sub is_float
{
  my ($a, $b, $test) = @_;
  ok(abs($a - $b) < 1e-4, $test);
}

my $t;

# testing time_threshold #######################################################
$t = new Term::TtyRec::Plus(infile         => $ttyrec,
                            time_threshold => .02);

my $trunc = 0;
my $trunc2 = 0;
while (my $frame_ref = $t->next_frame())
{
  $trunc += $frame_ref->{diff};
  $trunc2 += defined($frame_ref->{prev_timestamp}) ? $frame_ref->{timestamp} - $frame_ref->{prev_timestamp} : 0;
}

is_float($trunc,  $time_truncated, "time_threshold works with diffs");
is_float($trunc2, $time_truncated, "time_threshold works with timestamp - prev_timestamp");

# testing filehandle ###########################################################
open(my $handle, '<', $ttyrec);
$t = new Term::TtyRec::Plus(filehandle => $handle);

my $t_time = 0;
while (my $frame_ref = $t->next_frame())
{
  $t_time += $frame_ref->{diff};
}

is_float($t_time, $time, "filehandle argument works well enough");

# testing infile + filehandle ##################################################
open(my $handle2, '<', $ttyrec);
$t = new Term::TtyRec::Plus(filehandle => $handle2,
                            infile     => "t/simple.ttyrec");

$t_time = 0;
while (my $frame_ref = $t->next_frame())
{
  $t_time += $frame_ref->{diff};
}

is_float($t_time, $time, "filehandle takes precedence over infile");

# testing bzip2 on filehandle ##################################################
open(my $handle3, '<', 't/simple.ttyrec.bz2');
$t = new Term::TtyRec::Plus(filehandle => $handle3,
                            bzip2      => 1);

$t_time = 0;
while (my $frame_ref = $t->next_frame())
{
  $t_time += $frame_ref->{diff};
}

is_float($t_time, $time2, "bzip2 on a filehandle works");

# testing bzip2 on infile ######################################################
$t = new Term::TtyRec::Plus(infile => 't/simple.ttyrec.bz2');

$t_time = 0;
while (my $frame_ref = $t->next_frame())
{
  $t_time += $frame_ref->{diff};
}

is_float($t_time, $time2, "bzip2 on infile works");

