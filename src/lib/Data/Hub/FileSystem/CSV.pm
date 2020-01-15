package Data::Hub::FileSystem::CSV;
use strict;
use Perl::Module;
use Data::Hub::Util qw(:all);
use Data::Format::CSV qw(csv_parse);
use base qw(Data::Hub::FileSystem::Node);

sub __read_from_disk {
  my $self = shift;
  return unless $self->__path && -e $self->__path;
  # slurps the whole thing into memory... twice
  $self->__content(file_read($self->__path));
  $self->__data(csv_parse(
    path => $self->__path,
    delimiter => path_ext($self->__path) eq 'tsv' ? "\t" : ',',
  ));
}

sub __write_to_disk {
  die 'notimpl';
}

1;
