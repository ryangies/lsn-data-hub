package App::TMS::Repository;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Logical;
use Error::Programatic;
use Data::Hub;
use App::TMS::Common;
use App::TMS::Client;
use base 'App::Console::CommandScript';

our %USAGE = ();

# ------------------------------------------------------------------------------
# new - Constructor
# new
# new $repository_directory
# ------------------------------------------------------------------------------

sub new {
  my $classname = shift;
  my $repo = Data::Hub->new(shift);
  bless {repo=>$repo}, ref($classname) || $classname;
}

# ------------------------------------------------------------------------------
# Commands
# ------------------------------------------------------------------------------

$USAGE{status} = $App::TMS::Client::USAGE{status};
$USAGE{status}{summary} = 'Status of all clients';

sub status {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->_foreach_client('status', @_);
}

# ------------------------------------------------------------------------------

$USAGE{update} = $App::TMS::Client::USAGE{update};
$USAGE{update}{summary} = 'Update all clients';

sub update {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  $self->_foreach_client('update', @_);
}

# ------------------------------------------------------------------------------
# _get_clients - Get the clients array from the settings file
# _get_clients
# ------------------------------------------------------------------------------

sub _get_clients {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $clients = $self->{repo}{"$TMS_SETTINGS/clients"}
    or throwf Error::Logical "Not a template repository: %s\n",
      $self->{repo}->{'/'}->get_path;
  $clients;
}

# ------------------------------------------------------------------------------
# _foreach_client - Execute a command for each client
# _foreach_client $command, @arguments
# ------------------------------------------------------------------------------

sub _foreach_client {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $cmd = shift;
  foreach my $dir ($self->_get_clients->values) {
    printf "%-6s %s\n",
      -d $dir ? $STATUS_CLIENT_DIR : $STATUS_CLIENT_DIR_MISSING,
      $dir;
    next unless -d $dir;
    my $client = App::TMS::Client->new($dir);
    $client->exec($cmd, @_);
  }
}

1;

__END__
