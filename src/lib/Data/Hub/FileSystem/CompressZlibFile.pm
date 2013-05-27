package Data::Hub::FileSystem::CompressZlibFile;
use strict;
our $VERSION = 0;

use Perl::Module;
use Compress::Zlib;
use Data::Hub::Util qw(:all);
use Parse::Padding qw(padding);
use base qw(Data::Hub::FileSystem::File);

our $Deflate = deflateInit(-Level => Z_BEST_SPEED);
our $Inflate = inflateInit();

sub __read_from_disk {
  my $tied = shift;
  my ($c, $status) = $Inflate->inflate(file_read_binary($tied->__path));
  throw Error::Programatic $status unless $status == Z_OK;
  $tied->__content($c);
}

sub __write_to_disk {
  my $tied = shift;
  $Deflate->deflate($tied->__content);
  my ($c, $status) = $Deflate->flush;
  throw Error::Programatic $status unless $status == Z_OK;
  file_write_binary($tied->__path, $c);
}

1;

__END__

