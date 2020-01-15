package Data::Hub::FileSystem::JSONFile;
use strict;
use Perl::Module;
use JSON::XS qw();
use base qw(Data::Hub::FileSystem::HashFile);

sub __parse {
  my $tied = shift;
  my $str = shift; # source string
  my $data = shift; # destination hash
  my $json = JSON::XS->new;
  my $h = $$str ? $json->decode($$str) : {};
  return overlay($data, $h);
}

sub __format {
  my $tied = shift;
  my $data = shift;
  my $json = JSON::XS->new->ascii->pretty->canonical(1);
  my $str = $json->encode(clone($data, -pure_perl));
  return \$str;
}

sub __has_crown {
  my $c = shift or return;
  1;
}

1;

__END__
