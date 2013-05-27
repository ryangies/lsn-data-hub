package Time::Regex::Strftime;
use strict;
our $VERSION = 0.1;

use Time::Regex qw(:all);
use base qw(Time::Regex);
use Exporter qw(import);

our @EXPORT = ();
our @EXPORT_OK = @Time::Regex::EXPORT_OK;
our %EXPORT_TAGS = %Time::Regex::EXPORT_TAGS;

#
# A word on time zones.
#
# Keep your sanity = use %z and and numeric timezone offsets, e.g., +0400
#  
# Avoid %Z as strftime will emit zones which are not understood by strptime.
# Er, at least that's the way it is as I am using Time::Piece which embeds
# its own copy of the freebsd strptime function and I'm not running on 
# FreeBSD.
#
# Our RFC 822 date does not match %z unless it uses the numeric offsets (ANSI 
# standard X3.51-1975).  The regular expression for a RFC 822 timezone is
#
#   z => '([-+]\d{4}|[A-IK-Z]|UTC?|GMT|EST|EDT|CST|CDT|MST|MDT|PST|PDT)',
#
# The reason we do NOT use this is because C<Time::Piece->strptime> does not
# handle the alpha time-zone abbreviations.
#
# TODO: These regular expressions have correct back-references meaning an
# array of parts is returned using C<=~> for instance. We can use this to
# write a wrapper C<strptime> method which looks up the time-zone abbreviation
# and converts it to its numeric offset before passing to C<Time::Piece>.
#
# See also
#
#   http://tools.ietf.org/html/rfc822#section-5
#   /usr/share/zoneinfo
#

sub init {
  my $self = shift;
  # Conversion-Specifier Character to Regular Expression map
  $self->{csc_to_re} = {
    a => '(' . join('|', @{$$self{abday}}) . ')',
    A => '(' . join('|', @{$$self{day}}) . ')',
    b => '(' . join('|', @{$$self{abmon}}) . ')',
    B => '(' . join('|', @{$$self{mon}}) . ')',
    c => undef,
    C => $$self{num}{'00_99'},
    d => $$self{num}{'01_31'},
    D => undef,
    e => $$self{num}{'1_31'},
    F => undef,
    G => $$self{num}{'0000_9999'},
    g => $$self{num}{'00_99'},
    h => '(' . join('|', @{$$self{abmon}}) . ')',
    H => $$self{num}{'00_23'},
    I => $$self{num}{'01_12'},
    j => $$self{num}{'001_366'},
    k => $$self{num}{'0_23'},
    l => $$self{num}{'1_12'},
    m => $$self{num}{'01_12'},
    M => $$self{num}{'00_59'},
    n => "(\n)",
    p => "($$self{am_str}|$$self{pm_str})",
    P => '(' . lc($$self{am_str}) . '|' . lc($$self{pm_str}) . ')',
    r => undef,
    R => undef,
    s => $$self{num}{epoch_seconds},
    S => $$self{num}{'00_60'},
    t => "(\t)",
    T => undef,
    u => $$self{num}{'1_7'},
    U => $$self{num}{'00_53'},
    V => $$self{num}{'01_53'},
    w => $$self{num}{'0_6'},
    W => $$self{num}{'00_53'},
    x => undef,
    X => undef,
    y => $$self{num}{'00_99'},
    Y => $$self{num}{'0000_9999'},
    z => '([-+]\d{4})',
#   z => '([-+]\d{4}|[A-IK-Z]|UTC?|GMT|EST|EDT|CST|CDT|MST|MDT|PST|PDT)',
    Z => '((?i)[A-Za-z0-9\/_+-]+)',
    '+' => undef,
    '%' => '(%)',
  };
  # Regular expression which matches valid conversion characters
  $self->{csc_expr} = $self->_csc_expr;
  # Delayed values (aliases)
  $self->{csc_to_re}{r} = $self->compile($self->{t_fmt_ampm});
  $self->{csc_to_re}{F} = $self->compile('%Y-%m-%d');
  $self->{csc_to_re}{R} = $self->compile('%H:%M');
  $self->{csc_to_re}{T} = $self->compile('%H:%M:%S');
  $self->{csc_to_re}{c} = $self->compile($self->{d_t_fmt});
  $self->{csc_to_re}{D} = $self->compile($self->{d_us_fmt});
  $self->{csc_to_re}{x} = $self->compile($self->{d_fmt});
  $self->{csc_to_re}{X} = $self->compile($self->{t_fmt});
  $self->{csc_to_re}{'+'} = $self->compile($self->{lc_time});
  $self;
}

sub _csc_expr {
  my $self = shift;
  my $chars = join('', keys %{$$self{csc_to_re}});
  $chars =~ s/(\W)/\\$1/g;
  "[$chars]";
}

sub compile {
  my $self = shift;
  my $format = shift;
  my $re = $format;
  $re =~ s/(?<![^\%]\%)\%($$self{csc_expr})/$$self{csc_to_re}{$1}/g;
  $re;
}

1;

__END__

=head1 NOTES

# RFC 822 - %a, %d %b %Y %H:%M:%S %z

Alternative format modifiers B<E> and B<O> are not supported.

B<%s> - Seconds since the epoch is restricted to the 32-bit (10 digit) format.

B<%R, %T> - The colon in the format is hard coded as per the strftime man page.

B<%+> - LC_TIME is hard coded.

=cut
