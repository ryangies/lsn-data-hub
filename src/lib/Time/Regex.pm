package Time::Regex;
use strict;
our $VERSION = 0;
use Exporter qw(import);

use I18N::Langinfo qw(
  langinfo    ABDAY_1   DAY_1   ABMON_1   MON_1
  D_T_FMT     ABDAY_2   DAY_2   ABMON_2   MON_2
  AM_STR      ABDAY_3   DAY_3   ABMON_3   MON_3
  PM_STR      ABDAY_4   DAY_4   ABMON_4   MON_4
  T_FMT_AMPM  ABDAY_5   DAY_5   ABMON_5   MON_5
  D_FMT       ABDAY_6   DAY_6   ABMON_6   MON_6
  T_FMT       ABDAY_7   DAY_7   ABMON_7   MON_7
                                ABMON_8   MON_8
                                ABMON_9   MON_9
                                ABMON_10  MON_10
                                ABMON_11  MON_11
                                ABMON_12  MON_12
);

# When $t is in gmtime (for localtime, use %Z to get EDT, e.g.)
sub FMT_UTC       {'%a, %d %b %Y %H:%M:%S UTC'};
sub FMT_GMT       {'%a, %d %b %Y %H:%M:%S GMT'};
sub FMT_RFC822    {'%a, %d %b %Y %H:%M:%S %z'};
sub FMT_RFC3339   {'%Y-%m-%dT%H:%M:%SZ'};
sub FMT_HIRES     {'%s.%f'};

#sub FMT_ISO8601   {'%G-%I-%dT%H:%M:%S'};

our @FORMATS = qw(
  FMT_UTC
  FMT_GMT
  FMT_RFC822
  FMT_RFC3339
  FMT_HIRES
);

our @EXPORT = ();
our @EXPORT_OK = @FORMATS;
our %EXPORT_TAGS = (
  all => [@EXPORT_OK],
  formats => [@EXPORT_OK],
);

our %DEFAULT = (
  d_t_fmt     => langinfo(D_T_FMT),
  d_us_fmt    => '%m/%d/%y',
  am_str      => langinfo(AM_STR),
  pm_str      => langinfo(PM_STR),
  t_fmt_ampm  => langinfo(T_FMT_AMPM),
  d_fmt       => langinfo(D_FMT),
  t_fmt       => langinfo(T_FMT),
  lc_time     => '%a %b %e %H:%M:%S %Z %Y',
  d_sep       => '-',
  t_sep       => ':',
);

# Number ranges as regular expressions
$DEFAULT{num} = {
  '0_9'             => '(\d)',
  '00_99'           => '(\d{2})',
  '000_999'         => '(\d{3})',
  '0000_9999'       => '(\d{4})',
  '000_99999'       => '(\d{3,5})',
  '01_31'           => '(0[1-9]|[12]\d|3[01])',
  '1_31'            => '( [1-9]|[12]\d|3[01])',
  '00_23'           => '([01]\d|2[0-3])',
  '0_23'            => '( \d|1\d|2[0-3])',
  '01_12'           => '(0[1-9]|1[0-2])',
  '1_12'            => '( [1-9]|1[0-2])',
  '001_366'         => '(00[1-9]|0[1-9]\d|[12]\d\d|3[0-5]\d|36[0-6])',
  '00_59'           => '(0\d|[1-4]\d|5[0-9])',
  '00_60'           => '(0\d|[1-5]\d|60)',
  '1_7'             => '([1-7])',
  '00_53'           => '(0\d|[1-4]\d|5[0-3])',
  '01_53'           => '(0[1-9]|[1-4]\d|5[0-3])',
  '0_6'             => '([0-6])',
  'epoch_seconds'   => '(\d{1,10})',
};

# Abbreviated day names
$DEFAULT{abday} = [map { langinfo($_) } (
  ABDAY_1,
  ABDAY_2,
  ABDAY_3,
  ABDAY_4,
  ABDAY_5,
  ABDAY_6,
  ABDAY_7
)];

# Full day names
$DEFAULT{day} = [map { langinfo($_) } (
  DAY_1,
  DAY_2,
  DAY_3,
  DAY_4,
  DAY_5, 
  DAY_6,
  DAY_7
)];

# Abbreviated month names
$DEFAULT{abmon} = [map { langinfo($_) } (
  ABMON_1,
  ABMON_2,
  ABMON_3,
  ABMON_4, 
  ABMON_5,
  ABMON_6,
  ABMON_7,
  ABMON_8,
  ABMON_9,
  ABMON_10,
  ABMON_11,
  ABMON_12
)];

# Full month names
$DEFAULT{mon} = [map { langinfo($_) } (
  MON_1,
  MON_2,
  MON_3,
  MON_4,
  MON_5,
  MON_6,
  MON_7,
  MON_8,
  MON_9,
  MON_10,
  MON_11,
  MON_12
)];

sub new {
  my $pkg = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {@_}, $pkg;
  $self->{$_} ||= $DEFAULT{$_} for (keys %DEFAULT);
  $self->init();
  $self;
}

sub init {
  die "Abstract base method called";
}

sub compile {
  die "Abstract base method called";
}

sub match {
  my $self = shift;
  my $time = shift;
  my $format = shift;
  my $expr = $self->compile($format);
  $time =~ /^$expr$/;
}

sub compare {
  my $self = shift;
  my $time = shift;
  my @result = ();
  for (@_) {
    my $expr = $self->compile($_);
    push @result, $_ if $self->match($time, $_);
  }
  wantarray ? @result : $result[0];
}

1;
