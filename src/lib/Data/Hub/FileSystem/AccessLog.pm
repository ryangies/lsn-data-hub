package Data::Hub::FileSystem::AccessLog;
use strict;
our $VERSION = 0.2;

use Perl::Class;
use Perl::Module;
use List::Util qw(max);
use base qw(Perl::Class::Hash Data::Hub::Container);

sub new {
  shift->SUPER::new(listeners => []);
}

sub get_value {
  shift->{shift};
}

# ------------------------------------------------------------------------------
# set_value - Set the disk mtime value for a particular path.
# set_value $path, $mtime
# Returns C<$mtime>
# Pass C<0> for C<$mtime> to track attempts to access missing files.
# ------------------------------------------------------------------------------

sub set_value {
  my $self = shift;
  my $path = shift or return;
  my $mtime = shift;
  return unless defined $mtime;
  $self->{$path} = $mtime;
  for (@{$self->__->{'listeners'}}) {
    $_->{$path} = $mtime;
  }
  $mtime;
}

sub clear {
  my $self = shift;
  %$self = ();
  for (@{$self->__->{'listeners'}}) {
    confess "Undefined listener" unless defined $_;
    %{$_} = ();
  }
}

sub add_listener {
  my $self = shift;
  for (@_) {
    throw Error::IllegalArg unless isa($_, 'HASH');
    push @{$self->__->{'listeners'}}, $_;
  }
}

sub remove_listener {
  my $self = shift;
  foreach my $listener (@_) {
    my $i = 0;
    for (@{$self->__->{'listeners'}}) {
      if ($_ ne $listener) {
        $i++;
        next;
      }
      splice @{$self->__->{'listeners'}}, $i, 1;
      last;
    }
  }
}

sub max_logged_mtime {
  my $self = shift;
  my $result = 0;
  $result = max($result, $_) for grep {$_} values %$self;
  $result;
}

sub max_actual_mtime {
  my $self = shift;
  my $result = 0;
  foreach my $path (keys %$self) {
    my $stat = stat $path or return undef;
    $result = max($result, $stat->mtime);
  }
  $result;
}

sub max_unmodified_mtime {
  my $self = shift;
  my $result = 0;
  foreach my $path (keys %$self) {
    my $stat = stat $path or return;
    return 0 if $stat->mtime > $self->{$path};
    $result = max($result, $stat->mtime);
  }
  $result;
}

1;

__END__

=pod:summary Log of access to file-system resources which supports listeners

=pod:synopsis

=pod:description

=cut
