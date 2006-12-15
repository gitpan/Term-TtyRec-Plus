package Term::TtyRec::Plus;

use warnings;
use strict;
use Carp qw/croak/;

=head1 NAME

Term::TtyRec::Plus - read a ttyrec

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

C<Term::TtyRec::Plus> is a module that lets you read ttyrec files. The related module, L<Term::TtyRec|Term::TtyRec> is designed more for simple interactions. Plus gives you more information and, using a callback, lets you munge the data block and timestamp. It will do all the subtle work of making sure timing is kept consistent, and of rebuilding each frame header.

    use Term::TtyRec::Plus;

    my $ttyrec = Term::TtyRec::Plus->new();
    while ($frame_ref = $ttyrec->next_frame())
    {
      # do stuff with $frame_ref, e.g.
      $total_time += $frame_ref->{diff};
    }

=head1 CONSTRUCTOR AND STARTUP

=head2 new()

Creates and returns a new C<Term::TtyRec::Plus> object.

  my $ttyrec = Term::TtyRec::Plus->new();

=head3 Parameters

Here are the parameters that C<<Term::TtyRec::Plus->new>> recognizes.

=over 4

=item infile

The input filename. A value of C<"-">, which is the default, means C<STDIN>.

=item filehandle

The input filehandle. By default this is C<undef>; if you have already opened the ttyrec then you can pass its filehandle to the constructor. If both filehandle and infile are defined, filehandle is used.

=item time_threshold

The maximum difference between two frames, in seconds. If C<undef>, which is the default, there is no enforced maximum. The second most common value would be C<10>, which some ttyrec utilities (such as timettyrec) use.

=item frame_filter

A callback, run for each frame before returning the frame to the user of C<Term::TtyRec::Plus>. This callback receives three arguments: the frame text, the timestamp, and the timestamp of the previous frame. All three arguments are passed as scalar references. The previous frame's timestamp is C<undef> for the first frame. The return value is not currently looked at. If you modify the timestamp, the module will make sure that change is noted and respected in further frame timestamps. Modifications to the previous frame's timestamp are currently ignored.

  sub halve_frame_time
  {
    my ($data_ref, $time_ref, $prev_ref) = @_;
    $$time_ref = $$prev_ref + ($$time_ref - $$prev_ref) / 2
      if defined $$prev_ref;
    $$data_ref =~ s/Eidolos/Stumbly/g;
  }

=back

=head3 State

Furthermore, you can modify C<Term::TtyRec::Plus>'s initial state, if you want to. This could be useful if you are chaining multiple ttyrecs together; you could pass a different initial frame. Support for such chaining might be added in a future version.

=over 4

=item frame

The initial frame number. Default C<0>.

=item prev_timestamp

The previous frame's timestamp. Default C<undef>.

=item accum_diff

The accumulated difference of all frames seen so far; see the section on C<diffed_timestamp> in C<next_frame>'s return value. Default C<0>.

=item relative_time

The time passed since the first frame. Default C<0>.

=back

=cut

sub new
{
  my $class = shift;

  my $self =
  {
    # options
    infile              => "-",
    filehandle          => undef,
    time_threshold      => undef,
    frame_filter        => sub { @_ },

    # state
    frame               => 0,
    prev_timestamp      => undef,
    accum_diff          => 0,
    relative_time       => 0,

    # allow overriding of options *and* state
    @_,
  };

  bless $self, $class;
  
  if (defined($self->{filehandle}))
  {
    undef $self->{infile};
  }
  else
  {
    if ($self->{infile} eq '-')
    {
      $self->{filehandle} = *STDIN;
    }
    else
    {
      open($self->{filehandle}, '<', $self->{infile})
        or croak "Unable to open '$self->{infile}' for reading: $!";
    }
  }

  croak "Cannot have a negative time threshold"
    if defined($self->{time_threshold}) && $self->{time_threshold} < 0;

  return $self;
}

=head1 METHODS

=head2 next_frame()

next_frame reads and processes the next frame in the ttyrec. It accepts no arguments. On EOF, it will return undef. On malformed ttyrec input, it will die. If it cannot reconstruct the header of a frame (which might happen if the callback sets the timestamp to -1, for example), it will die. Otherwise, a hash reference is returned with the following fields set.

=over 4

=item data

The frame data, filtered through the callback. The original data block is not made available.

=item orig_timestamp

The frame timestamp, straight out of the file.

=item diffed_timestamp

The frame timestamp, with the accumulated difference of all of the previous frames applied to it. This is so consistent results are given. For example, if your callback adds three seconds to frame 5's timestamp, then frame 6's diffed timestamp will take into account those three seconds, so frame 6 happens three seconds later as well. So the net effect is frame 4 is extended by three seconds.

=item timestamp

The diffed timestamp, filtered through the callback.

=item prev_timestamp

The previous frame's timestamp (after diffing and filtering; the originals are not made available).

=item diff

The difference between the current frame's timestamp and the previous frame's timestamp. Yes, it is equivalent to C<timestamp - prev_timestamp>, but it is provided for convenience. On the first frame it will be C<0> (not C<undef>).

=item orig_header

The 12-byte frame header, straight from the file.

=item header

The 12-byte frame header, reconstructed from C<data> and C<timestamp> (so, after filtering, etc.).

=item frame

The frame number, using 1-based indexing.

=item relative_time

The time between the first frame's timestamp and the current frame's timestamp.

=back

=cut

sub next_frame
{
  my $self = shift;
  $self->{frame}++;

  my $hgot = read $self->{filehandle}, my $hdr, 12;
  
  # clean EOF
  return if $hgot == 0;

  croak "Expected 12-byte header, got $hgot"
    if $hgot != 12;

  my @hdr = unpack "VVV", $hdr;

  my $orig_timestamp = $hdr[0] + $hdr[1] / 1_000_000;
  my $diffed_timestamp = $orig_timestamp + $self->{accum_diff};
  my $timestamp = $diffed_timestamp;

  my $old_timestamp = $timestamp;

  if (defined($self->{time_threshold}) && 
      defined($self->{prev_timestamp}) && 
      $timestamp - $self->{prev_timestamp} > $self->{time_threshold})
  {
    $timestamp = $self->{prev_timestamp} + $self->{time_threshold};
    $self->{accum_diff} = $timestamp - $old_timestamp;
    $old_timestamp = $timestamp;
  }

  my $dgot = read $self->{filehandle}, my ($data), $hdr[2];

  croak "Expected $hdr[2]-byte frame, got $dgot"
    if $dgot != $hdr[2];

  my $prev_timestamp = $self->{prev_timestamp};

  $self->{frame_filter}(\$data, \$timestamp, \$self->{prev_timestamp});

  $self->{prev_timestamp} = $timestamp;

  my $diff = defined($prev_timestamp) ? $timestamp - $prev_timestamp : 0;

  $self->{relative_time} += $diff
    unless $self->{frame} == 1;

  $self->{accum_diff} += $timestamp - $old_timestamp;

  $hdr[0] = int($timestamp);
  $hdr[1] = int(1_000_000 * ($timestamp - $hdr[0]));
  $hdr[2] = length($data);

  my $newhdr =   pack "VVV", @hdr;
  my @newhdr = unpack "VVV", $newhdr;

  croak "Unable to create a new header, seconds portion of timestamp: want to write $hdr[0], can only write $newhdr[0]"
    if $hdr[0] != $newhdr[0];

  croak "Unable to create a new header, microseconds portion of timestamp: want to write $hdr[1], can only write $newhdr[1]"
    if $hdr[1] != $newhdr[1];

  croak "Unable to create a new header, frame length: want to write $hdr[2], can only write $newhdr[2]"
    if $hdr[2] != $newhdr[2];


  return
  {
    data             => $data,
    orig_timestamp   => $orig_timestamp,
    diffed_timestamp => $diffed_timestamp,
    timestamp        => $timestamp,
    prev_timestamp   => $prev_timestamp,
    diff             => $diff,
    orig_header      => $hdr,
    header           => $newhdr,
    frame            => $self->{frame},
    relative_time    => $self->{relative_time},
  };
}

=head2 infile()

Returns the infile passed to the constructor. If a filehandle was passed, this will be C<undef>.

=cut

sub infile
{
  $_[0]->{infile};
}

=head2 filehandle()

Returns the filehandle passed to the constructor, or if C<infile> was used, a handle to it.

=cut

sub filehandle
{
  $_[0]->{filehandle};
}

=head2 time_threshold()

Returns the time threshold passed to the constructor. By default it is C<undef>.

=cut

sub time_threshold
{
  $_[0]->{time_threshold};
}

=head2 frame_filter()

Returns the frame filter callback passed to the constructor. By default it is C<sub { @_ }>.

=cut

sub frame_filter
{
  $_[0]->{frame_filter};
}

=head2 frame()

Returns the number of the most recently returned frame.

=cut

sub frame
{
  $_[0]->{frame};
}

=head2 prev_timestamp()

Returns the timestamp of the most recently returned frame.

=cut

sub prev_timestamp
{
  $_[0]->{prev_timestamp};
}

=head2 relative_time()

Returns the time so far since the first frame.

=cut

sub relative_time
{
  $_[0]->{relative_time};
}

=head2 accum_diff()

Returns the total time difference between timestamps and . C<accum_diff> is added to the timestamp before it is passed to the C<frame_filter> callback.

=cut

sub accum_diff
{
  $_[0]->{accum_diff};
}

=head1 AUTHOR

Shawn M Moore, C<< <sartak at gmail.com> >>

=head1 CAVEATS

=over 4

=item *
Ttyrecs are frame-based. If you are trying to modify a string that is broken across multiple frames, it will not work. Say you have a ttyrec that prints "foo" in frame one and "bar" in frame two, both with the same timestamp. In a ttyrec player, it might look like these are one frame (with data "foobar"), but it's not. There is no easy, complete way to add arbitrary substitutions; you would have to write (or reuse) a terminal emulator.

=item *
If you modify the data block, weird things could happen. This is especially true of escape-code-littered ttyrecs (such as those of NetHack). For best results, pretend the data block is an executable file; changes are OK as long as you do not change the length of the file. It really depends on the ttyrec though.

=item *
If you modify the timestamp of a frame so that it is not in sequence with other frames, the behavior is undefined (it is up to the client program). C<Term::TtyRec::Plus> will not reorder the frames for you.

=back

=head1 BUGS

Please report any bugs or feature requests to
C<bug-term-ttyrec-supercharged at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Term-TtyRec-Plus>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Term::TtyRec::Plus

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Term-TtyRec-Plus>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Term-TtyRec-Plus>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Term-TtyRec-Plus>

=item * Search CPAN

L<http://search.cpan.org/dist/Term-TtyRec-Plus>

=back

=head1 ACKNOWLEDGEMENTS

Thanks to Sean Kelly for always being the catalyst. Thanks also to brian d foy for writing "How a script becomes a module".

=head1 COPYRIGHT & LICENSE

Copyright 2006 Shawn M Moore, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Term::TtyRec::Plus
