package Data::Format::HexString;
use strict;
our $VERSION = 0.1;

use Exporter qw(import);
use Perl::Module;
use Error::Programatic;

our @EXPORT_OK = qw(hexstr_parse hexstr_format);
our %EXPORT_TAGS = (all=>[@EXPORT_OK]);

# ------------------------------------------------------------------------------
# hexstr_format - Create hexed string
# ------------------------------------------------------------------------------
#|test(match) use Data::Format::HexString qw(:all);
#|hexstr_format( 'Dogs (Waters, Gilmour) 17:06' );
#=Dogs_0x20__0x28_Waters_0x2c__0x20_Gilmour_0x29__0x20_17_0x3a_06
# ------------------------------------------------------------------------------

sub hexstr_format {
  my $str = shift;
  $str =~ s/([^A-Za-z0-9_])/sprintf("_0x%2x_", unpack("C", $1))/eg;
  $str;
}

# ------------------------------------------------------------------------------
# hexstr_parse - Parse hexed string
# ------------------------------------------------------------------------------
#|test(match) hexstr_parse('Dogs_0x20__0x28_Waters_0x2c__0x20_Gilmour_0x29__0x20_17_0x3a_06');
#=Dogs (Waters, Gilmour) 17:06
# ------------------------------------------------------------------------------

sub hexstr_parse {
  my $str = shift;
  $str =~ s/_0x([a-fA-F0-9][a-fA-F0-9])_/pack("C",hex($1))/eg;
  $str
}

1;

__END__
