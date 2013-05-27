package Data::Format::Nml;
use strict;
our $VERSION = 0;

use Exporter qw(import);
use Perl::Module;
use Error::Logical;
use Data::Format::Nml::Document;

our @EXPORT = qw();
our @EXPORT_OK = qw(
  nml_parse
  nml_format
);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);

# ------------------------------------------------------------------------------
# nml_parse - Parse a string into Perl data structures
# ------------------------------------------------------------------------------

sub nml_parse ($) {
  my $txt = shift;
  $txt =~ s/</&lt;/g;
  $txt =~ s/>/&gt;/g;
  my $doc = Data::Format::Nml::Document->new($txt);
  $doc->{root};
}

# ------------------------------------------------------------------------------
# nml_format - Parse Perl data structures into a string
# ------------------------------------------------------------------------------

sub nml_format {
  croak 'nml_format is not (yet) implemented';
}

1;

__END__

=pod:summary Parse/format routines for NML (No mark-up language)

=pod:synopsis

  use Data::Format::Nml qw(nml_parse);
  my $hash = nml_parse($text);

See Data::Format::Nml::Document;

=cut
