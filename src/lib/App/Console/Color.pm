package App::Console::Color;
use strict;
use Term::ANSIColor qw(:constants);
use Exporter qw(import);
our $VERSION = 0.1;
our @EXPORT = qw();
our @EXPORT_OK = qw(c_length c_sprintf c_printf c_stripf);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);

our %ColorAlias = (
  '^'=>BOLD,      '*'=>REVERSE,
  'r'=>RED,       'R'=>RED.BOLD,
  'g'=>GREEN,     'G'=>GREEN.BOLD,
  'b'=>BLUE,      'B'=>BLUE.BOLD,
  'y'=>YELLOW,    'Y'=>YELLOW.BOLD,
  'm'=>MAGENTA,   'M'=>MAGENTA.BOLD,
  'c'=>CYAN,      'C'=>CYAN.BOLD,
);

our $ColorChars = join '', keys %ColorAlias;

sub c_length {
  my $len = 0;
  for (@_) {
    my $strcpy = $_;
    $strcpy =~ s/(\e.*?m)//g;
    $len += length($strcpy);
  }
  $len;
}

sub c_sprintf ($@) {
  my $str = shift;
  $str =~ s/(?<!%)%_([$ColorChars])([ \+\-0#]?[\*\$\w\{\}\.\d]+)/$ColorAlias{$1}.'%'.$2.RESET/eg;
  sprintf $str, @_;
}

sub c_stripf ($@) {
  my $str = shift;
  $str =~ s/(?<!%)%_([$ColorChars])([ \+\-0#]?[\*\$\w\{\}\.\d]+)/%$2/g;
  sprintf $str, @_;
}

sub c_printf ($@) {
  my $out = ref($_[0]) ? shift : \*STDOUT;
  my $str = -t $out ? c_sprintf(shift, @_) : c_stripf(shift, @_);
  print $out $str;
}

1;

__END__

=pod:synopsis

  use App::Console::Color qw(:all);
  c_printf("%_bs %_rs\n", 'Blue', 'Red');

  my $str = c_sprintf("%_bs %_rs\n", 'Blue', 'Red');
  my $len = c_length($str); # because length(str) counts the ctrl chars

=pod:description

Extends C<printf> and C<sprintf> with coloring.  Where normally one would
write:

  %s

one can write:

  %_bs

and the value will be printed in blue.  The trigger is the underscore
character, and the color-code is the following character (See `Color Codes`).

  %_bs
   ^^^
   |||___ 's' means this will become %s when given to sprintf
   ||____ 'b' meaning blue (see below)
   |_____ '_' triggers this color parsing

This is not limited to the string conversion as only the trigger and color-code
are pruned before C<sprintf> is called.

  Normal (No Color)     Enhanced (using 'b' for blue)
  --------------------- -----------------------------
  %-10s                 %_b-10s
  %02d                  %_b02d
  %u                    %_bu

Bold and reverse color sequences are included.  Bold colors use the
the upper-case letter of the color code.

  %_^s        just bold  (color code is '^')

Color Codes

  '^'=>BOLD,      '*'=>REVERSE,
  'r'=>RED,       'R'=>RED.BOLD,
  'g'=>GREEN,     'G'=>GREEN.BOLD,
  'b'=>BLUE,      'B'=>BLUE.BOLD,
  'y'=>YELLOW,    'Y'=>YELLOW.BOLD,
  'm'=>MAGENTA,   'M'=>MAGENTA.BOLD,
  'c'=>CYAN,      'C'=>CYAN.BOLD,

=cut
