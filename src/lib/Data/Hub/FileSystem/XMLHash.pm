package Data::Hub::FileSystem::XMLHash;
use strict;
use Perl::Module;
use Data::Format::Xml qw(xml_parse xml_format);
use base qw(Data::Hub::FileSystem::HashFile);

sub __parse {
  my $tied = shift;
  my $str = shift; # source string
  my $data = shift; # destination hash
  my $h = $$str ? xml_parse($$str) : {};
  return overlay($data, $h);
}

sub __format {
  my $tied = shift;
  my $data = shift;
  my $str = xml_format($data, -indent => '  ');
  return \$str;
}

sub __has_crown {
  my $c = shift or return;
  1;
}

1;

__END__
