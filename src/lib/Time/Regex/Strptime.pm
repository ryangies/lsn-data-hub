package Time::Regex::Strptime;
use strict;
our $VERSION = 0;

use Time::Regex qw(:all);
use Time::Regex::Strftime;
use Exporter qw(import);

our @ISA = qw(Time::Regex::Strftime);
our @EXPORT = ();
our @EXPORT_OK = @Time::Regex::EXPORT_OK;
our %EXPORT_TAGS = %Time::Regex::EXPORT_TAGS;

sub init {
  my $self = shift;
  # The number-range constants differ as strptime is lenient in its requirements
  # for leading zeros and spaces.
  $self->{num}{'01_31'} = '(0?[1-9]|[12]\d|3[01])';
  $self->{num}{'1_31'} = '( ?[1-9]|[12]\d|3[01])';
  $self->{num}{'00_23'} = '([01]\d|2[0-3])';
  $self->{num}{'0_23'} = '( ?\d|1\d|2[0-3])';
  $self->{num}{'01_12'} = '(0?[1-9]|1[0-2])';
  $self->{num}{'1_12'} = '( ?[1-9]|1[0-2])';
  $self->{num}{'00_59'} = '(0?\d|[1-4]\d|5[0-9])';
  $self->{num}{'00_60'} = '(0?\d|[1-5]\d|60)';
  $self->{num}{'00_53'} = '(0?\d|[1-4]\d|5[0-3])';
  $self->{num}{'01_53'} = '(0?[1-9]|[1-4]\d|5[0-3])';
  Time::Regex::Strftime::init($self);
}

1;

__END__

=pod:notes

# RFC 822 - %a, %d %b %Y %H:%M:%S %z

Alternative format modifiers B<E> and B<O> are not supported.

B<%s> - Seconds since the epoch is restricted to the 32-bit (10 digit) format.

B<%R, %T> - The colon in the format hard coded as per the strftime man page.

B<%+> - LC_TIME is hard coded.

=cut
