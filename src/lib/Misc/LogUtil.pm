package Misc::LogUtil;
use strict;
use Time::Piece;
use Time::Regex::Strftime qw(FMT_RFC822);
use Misc::Stopwatch;
our $VERSION = 0.1;

# ------------------------------------------------------------------------------
# new - Construct a new instance
# new
# new $stopwatch
# where:
#   $stopwatch  isa Misc::Stopwatch
# ------------------------------------------------------------------------------
#|test(!abort) # Create a new instance
#|use Misc::LogUtil;
#|Misc::LogUtil->new();
# ------------------------------------------------------------------------------

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = bless [@_], $class;
  unless ($self->get_stopwatch) {
    my $sw = Misc::Stopwatch->new;
    $sw->reset->start();
    $self->set_stopwatch($sw);
  }
  $self;
}

sub set_stopwatch   { $_[0]->[0] = $_[1]; }
sub get_stopwatch   { $_[0]->[0]; }

# ------------------------------------------------------------------------------
# debug - Write a debug message to the apache log
# debug $message
# ------------------------------------------------------------------------------

sub debug { shift->message('debug', @_); }

# ------------------------------------------------------------------------------
# warn - Write a warning to the apache log
# warn $warn
# ------------------------------------------------------------------------------

sub warn { shift->message('warn', @_); }

# ------------------------------------------------------------------------------
# error - Write an error to the apache log
# error $error
# ------------------------------------------------------------------------------

sub error { shift->message('error', @_); }

# ------------------------------------------------------------------------------
# notice - Write a notice to the apache log
# notice $notice
# ------------------------------------------------------------------------------

sub notice { shift->message('notice', @_); }

# ------------------------------------------------------------------------------
# info - Write an informational message to the apache log
# info $message
# ------------------------------------------------------------------------------

sub info { shift->message('info', @_); }

# ------------------------------------------------------------------------------
# message - Write to the apache log
# message $LOG_TYPE, $message
# ------------------------------------------------------------------------------

sub message {
  my $self = shift;
  my $type = shift;
  my $sw = $self->get_stopwatch;
  my $elapsed = $sw ? $sw->elapsed : 0;
  my $timestamp = localtime->strftime(FMT_RFC822);
  my @caller = caller(1);
  my $fmt = '[%s] [%s] <%s:%s> [%d] [%.4f] %s';
  my $msg = sprintf($fmt, $timestamp, $type, $caller[1], $caller[2], $$, $elapsed, join('', @_));
  my $result = CORE::warn $msg . "\n";
  $result;
}

1;

__END__

=pod:summary Simple logging utility with run-time context

=pod:synopsis

  use Misc::LogUtil;
  my $log = Misc::LogUtil->new();

Or, to capture elapsed time:

  use Misc::LogUtil;
  use Misc::Stopwatch;
  my $sw = Misc::Stopwatch->new;
  my $log = Misc::LogUtil->new($sw);
  $sw->reset->start(); # Elapsed time starts now

Call logging methods:

  $log->error('The code is smoking');
  $log->warn('The code is hot');
  $log->notice('The code is warm');
  $log->info('The code is lighting up');
  $log->debug('The code is doing what?');

=pod:description

Log-file entries are formatted as:

   .--------------------------------------------- 1) Date and time
   |     .--------------------------------------- 2) Logging level
   |     |      .-------------------------------- 3) Filename and line number
   |     |      |           .-------------------- 4) Process ID, i.e., $$
   |     |      |           |       .------------ 5) Elapsed time
   |     |      |           |       |       .---- 6) Log Message
   |     |      |           |       |       |
   |     |      |           |       |       |
   v     v      v           v       v       v
  [...] [warn] <test.pl:5> [22933] [0.0229] ...

=pod:seealso

  Misc::Stopwatch

=cut
