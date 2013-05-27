package Data::Hub::FileSystem::File;
use strict;
our $VERSION = 0;

use base qw(Data::Hub::FileSystem::Node);
use Perl::Module;
use Data::Hub::Util qw(:all);

sub __read_from_disk {
  my $tied = shift;
  tie my $c, 'Data::Hub::FileSystem::File::Content', $tied->__path;
  $tied->__content($c);
}

sub __write_to_disk {
  my $tied = shift;
  file_write($tied->__path, $tied->__content);
}

sub __content {
  my $tied = shift;
  $tied->__raw_content(@_);
}

1;

package Data::Hub::FileSystem::File::Content;
use strict;
our $VERSION = 0;

use Data::Hub::Util qw(:all);

sub TIESCALAR { bless [$_[1], undef], $_[0]; }

sub FETCH { defined $_[0][1]
  ? $_[0][1]
  : $_[0][1] = -e $_[0][0]
    ? file_read($_[0][0])
    : undef;
}
sub STORE { $_[0][1] = $_[1]; }

1;

__END__
