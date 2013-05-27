package Data::Hub::FileSystem::BinaryFile;
use strict;
our $VERSION = 0;

use base qw(Data::Hub::FileSystem::File);
use Perl::Module;
use Data::Hub::Util qw(:all);

sub __read_from_disk {
  my $tied = shift;
}

sub __write_to_disk {
  my $tied = shift;
  file_write_binary($tied->__path, $tied->__content);
}

1;

__END__
