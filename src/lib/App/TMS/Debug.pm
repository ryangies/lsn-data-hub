package App::TMS::Debug;
use strict;
use Parse::Template::Debug::Listener;
our $VERSION = 0;

use Perl::Module;
use Error::Programatic;
use Data::Hub::Util qw(addr_normalize);

our $P = undef;

sub attach {
  $P = shift or throw Error::MissingArg;
  $P->{dbgout} = Parse::Template::Debug::Listener->new(\&on_step);
}

sub detach {
  undef $P->{dbgout};
}

sub on_step {
  my $sig = shift;
  if ($sig eq 'SIG_UNDEFINED') {
    my $ctx = $P->get_ctx;
    my $elem = $ctx->{elem};
    warnf "Undefined value: '%s' in template '%s' at char: %d\n",
      $elem->{t}, addr_normalize("$ctx->{path}/$ctx->{name}"), $elem->{B} + 1;
  }
}

1;

__END__
