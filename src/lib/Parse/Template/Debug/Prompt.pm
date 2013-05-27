package Parse::Template::Debug::Prompt;
use strict;
our $VERSION = 0;

use Perl::Module;
use Error::Programatic;
use App::Console::Prompts qw(:all);
use App::Console::Color qw(:all);
use Data::Hub::Util qw(addr_normalize);
use Parse::Template::Debug::Listener;

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
    my $var = $elem->{t};
    my $t = c_sprintf ('Value for %_gs', $var);
    my $value = prompt($t);
    $ctx->{vars}->set($var, $value); # re-use within scope
    $elem->{value_override} = $value;
  }
}

1;

__END__
