package Data::Hub::FileSystem::ImageFile;
use strict;
our $VERSION = 0;

use base qw(Data::Hub::FileSystem::BinaryFile);
use Perl::Module;
use Data::Hub::Util qw(:all);

# We are setup to store metadata in the data segment of this node. Currently
# EXIF information is populated. XMP information should be implemented in the
# same manner (deferring until called upon) and stored in $$data{'XMP'}.

sub get_description {
  my $self = shift;
  my $result = undef;
  for (qw(Description ImageDescription Caption-Abstract Comment UserComment XPComment)) {
    $result = $$self{'EXIF'}{$_} and last;
  }
  $result;
}

sub __read_from_disk {
  my $tied = shift;
  my $data = $tied->__data();
  # Delay reading of EXIF information until called upon
  tie my %info, 'Data::Hub::FileSystem::ImageFile::ExifInfo', $tied->__path;
  $$data{'EXIF'} = \%info;
}

sub __write_to_disk {
  my $tied = shift;
  my $data = $tied->__data();
  my $exif = $$data{'EXIF'};
  my $info = tied %$exif;
  if ($info->get_modify_count > 0) {
    $info->save();
  }
}

1;

package Data::Hub::FileSystem::ImageFile::ExifInfo;
use strict;
use Image::ExifTool qw(:Public);
use Tie::Hash;
use base qw(Tie::ExtraHash);

# On-demand hash which populates EXIF metadata

sub TIEHASH {
  my $pkg = shift;
  my $path = shift;
  return bless [
    undef,                      # Populated EXIF information
    $path,                      # Full path to image file
    undef,                      # EXIF Tool object
    0,                          # Modify count
  ], $pkg;
}

sub get_modify_count {
  return $_[0][3];
}

sub save {
  $_[0][2]->WriteInfo($_[0][1]);
}

sub FIRSTKEY {
  $_[0]->__populate;
  my $a = scalar keys %{$_[0][0]};
  each %{$_[0][0]};
}

sub FETCH {
  $_[0]->__populate;
  my $k = $_[1];
  $_[0][0]{$k};
}

sub STORE {
  $_[0]->__populate;
  my $k = $_[1];
  my $v = $_[2];
  $_[0][0]{$k} = $v;
  $_[0][2]->SetNewValue($k, $v);
  $_[0][3]++;
}

sub __populate {
  return if defined $_[0][0]; # has populated
  $_[0][0] = {};
  my $path = $_[0][1];
  my $exif_tool = Image::ExifTool->new();
  $exif_tool->ExtractInfo($path);
  for (sort $exif_tool->GetFoundTags()) {
    $_[0][0]{$_} = $exif_tool->GetValue($_);
  }
  $_[0][2] = $exif_tool;
  $_[0];
}

1;
