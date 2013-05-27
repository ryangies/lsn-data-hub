package Misc::Time;
use strict;
use Exporter qw(import);
use Perl::Module;
use Error::Programatic;

our $VERSION = 0.1;
our @EXPORT = qw();

our @EXPORT_STD = qw(
  time_dhms
  time_ymdhms
  time_apr_to_hires
);

our @EXPORT_CONST = qw(
  ONE_SECOND
  ONE_MINUTE
  ONE_HOUR
  ONE_DAY
  ONE_WEEK
  ONE_YEAR
  ONE_MONTH
);

our @EXPORT_OK = (@EXPORT_CONST, @EXPORT_STD);
our %EXPORT_TAGS = (
  const => [@EXPORT_CONST],
  std => [@EXPORT_STD],
  all => [@EXPORT_OK],
);

use constant ONE_SECOND   => 1;
use constant ONE_MINUTE   => ONE_SECOND * 60;
use constant ONE_HOUR     => ONE_MINUTE * 60;
use constant ONE_DAY      => ONE_HOUR * 24;
use constant ONE_WEEK     => ONE_DAY * 7;
use constant ONE_YEAR     => ONE_WEEK * 52;
use constant ONE_MONTH    => ONE_YEAR / 12;

# ------------------------------------------------------------------------------
# time_dhms - Split the provided seconds into days, hours, minutes, and seconds.
# time_dhms $seconds
#
#   my ($days, $hours, $min, $sec) = time_dhms(time);
# ------------------------------------------------------------------------------

sub time_dhms {
  my $s = shift;
  throw Error::MissingArg unless defined $s;
  $s = sprintf('%d', abs($s));
  my ($d, $h, $m) = (0, 0, 0);
  $d = int($s/86400);
  $s -= ($d * 86400);
  $h = int($s/3600);
  $s -= ($h * 3600);
  $m = int($s/60);
  $s -= ($m * 60);
  return ($d, $h, $m, $s);
}

# ------------------------------------------------------------------------------
# time_ymdhms - Split the provided seconds into years, months, days, hours, minutes, and seconds.
# time_ymdhms $seconds
#
#   my ($years, $months, $days, $hours, $min, $sec) = time_ymdhms(time);
#
# WARNING: This is currently a rough estimation, using 365 days/year and
# 30 days/month.
# ------------------------------------------------------------------------------

sub time_ymdhms {
  my $seconds = shift;
  throw Error::MissingArg unless defined $seconds;
  my ($d, $h, $m, $s) = time_dhms($seconds);
  my ($y, $M) = (0, 0);
  $y = int($d/365);
  $d -= ($y * 365);
  $M = int($d/30);
  $d -= ($M * 30);
  return ($y, $M, $d, $h, $m, $s);
}

# ------------------------------------------------------------------------------
# time_apr_to_hires - Convert apr time string to perl hires string
# time_apr_to_hires $time
# ------------------------------------------------------------------------------
#|test(!abort) use Misc::Time qw(:all);
#|test(match) # Simple time string conversion
#|time_apr_to_hires('1193094188212812');
#=1193094188.212812
# ------------------------------------------------------------------------------

sub time_apr_to_hires {
  join('.', $_[0] =~ /(\d+)(\d{6})$/);
};

1;
