package Data::Hub::FileSystem::YAMLFile;
use strict;
use Perl::Module;
use YAML::XS qw();
use base qw(Data::Hub::FileSystem::HashFile);

# ------------------------------------------------------------------------------
# The YAML::XS Load and Dump methods expect and return octets, so we disable the
# utf8 io layer.
# ------------------------------------------------------------------------------

sub __rw_utf8 {
  0;
}

sub __parse {
  my $tied = shift;
  my $str = shift; # source string
  my $data = shift; # destination hash
  my $h = YAML::XS::Load($$str);
  return overlay($data, $h);
}

sub __format {
  my $tied = shift;
  my $data = shift;
  my $str = YAML::XS::Dump(clone($data, -pure_perl));
  return \$str;
}

sub __has_crown {
  my $c = shift or return;
  1;
}

1;

__END__
