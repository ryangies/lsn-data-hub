package Parse::Template::Debug::Debugger;
use strict;
use App::Console::Color qw(:all);
use Term::ANSIColor qw(:constants);
our $VERSION = 0.1;

use Perl::Module;
use Data::Hub::Util qw(:all);
use Data::Format::Hash qw(hf_format);
use Parse::StringToken qw(str_token);
use Parse::Template::Debug::Listener;
use Tie::Scalar;
use Term::ReadLine;
use Error::Programatic;
use Term::Size;

our $P = undef;
our $Term = new Term::ReadLine 'parser debugger';
our $OUT = $Term->OUT || \*STDOUT;
our $Prompt = '> ';
our $Stdout = undef;
our ($Cols, $Rows) = Term::Size::chars *STDOUT{IO};

sub attach {
  $SIG{'__DIE__'} = \&_sig_die;
  $SIG{'__WARN__'} = \&_sig_warn;
  $P = shift or throw Error::MissingArg;
  $P->{dbgout} = Parse::Template::Debug::Listener->new(\&on_step);
  $Stdout = select ($OUT);
}

sub detach {
  select ($Stdout);
}

# Callback

our $Step_Over = 1;
our $Step_Out = 0;
our $Jump = 0;
our $Level = 1;

sub on_step {
# $Term->tkRunning(1);
# local $SIG{'__DIE__'} = \&_sig_die;
# local $SIG{'__WARN__'} = \&_sig_warn;
  local $SIG{'WINCH'} = sub { ($Cols, $Rows) = Term::Size::chars *STDOUT{IO}; };
  $Term->ornaments(0);
  local $Color::Out = $OUT;
  $| = 1;
  my $sig = shift;
  my $ctx = $P->get_ctx;
  my $depth = @{$P->{ctx}};
  my $show_prompt = 1;
  if ($sig eq 'SIG_BEGIN') {
  } elsif ($sig eq 'SIG_END') {
  } elsif ($sig eq 'SIG_UNDEFINED') {
    $show_prompt = 0;
  } elsif ($sig eq 'SIG_MATCH') {
    if ($Step_Out) {
      return if $depth > $Step_Out;
      $Step_Out = 0;
    }
    return if $Step_Over && $depth > $Level;
    $Level = $depth;
    # Definition
    _list_source() unless $Jump;
  }
  return unless $show_prompt;
  while (defined ($_ = $Term->readline(_prompt($depth, $ctx, $Jump).$Prompt))) {
    print $OUT RESET;
    s/\s+$//;
    my @args = str_token($_)->split;
    last unless @args;
    my $cmd = shift @args;

    if ($cmd && $cmd !~ /^[qjnsrpxecCXVTlo?h]$/) {
      warn "No such command: $cmd (use h|? for help)\n";
      next;
    }

    $cmd eq ''  and last;
    $cmd eq 'q' and exit;
    $cmd eq 'j' and _toggle_jump_mode();
    $cmd eq 'n' and do {$Step_Over = 1; last;};
    $cmd eq 's' and do {$Level = $depth + 1; $Step_Over = 0; last;};
    $cmd eq 'r' and do {$Step_Out = $Level = $depth - 1; last;};
    $cmd eq 'p' and _print(@args);
    $cmd eq 'x' and _dump(@args);
    $cmd eq 'e' and _dump(@args);
    $cmd eq 'c' and _dump_context_vars(@args);
    $cmd eq 'C' and _dump_context_vars(-1);
    $cmd eq 'X' and _dump_local_stack(0);
    $cmd eq 'V' and _dump_local_stack(@args);
    $cmd eq 'T' and _stack_trace(@args);
    $cmd eq 'l' and _list_source(@args);
    $cmd eq 'o' and _list_output(@args);
    $cmd eq '?' and _qhelp(@args);
    $cmd eq 'h' and _qhelp(@args);
  }
}

sub _toggle_jump_mode {
  $Jump = !$Jump;
  c_printf 'Jump mode: %_^s' . "\n", $Jump ? 'on' :  'off';
}

sub _prompt {
  my ($depth, $ctx, $show_match) = @_;
  unless ($depth > 0) {
    return c_sprintf '%_bd::%_bs(%_bs:%_Bd/%_bd) ', 0, '', '', 0, 0;
  }
  my $prompt = c_sprintf '%_bd::%_bs(%_bs:%_Bd/%_bd) ',
    $depth, $ctx->{path} || '', $ctx->{name} || '', $ctx->{elem}{B}, $ctx->{len};
  if ($show_match) {
    $prompt .= c_sprintf '%_cs' . "\n", substr(${$ctx->{text}} || '', $ctx->{elem}{B}, $ctx->{elem}{W});
  }
  $prompt;
}

# Commands

sub _list_leader {
  my $ctx = $P->get_ctx;
  my $w = $ctx->{elem}{B} - $ctx->{pos};
  print $OUT substr(${$ctx->{text}}, $ctx->{pos}, $w);
}

sub _get_ctx {
  my $level = shift;
  my $depth = @{$P->{ctx}};
  $level = $depth unless defined $level;
  unless (is_numeric($level)) {
    warn "Not a number: $level\n";
    return;
  }
  return if ($level == 0);
  if ($level > $depth || $level < 0) {
    warn "No such level: $level$/";
    return;
  }
  $level -= $depth; # inverse
  $level *= -1;
  $P->{ctx}->[$level] or throw Error::Programatic;
}

sub _get_elem_text {
  my $ctx = _get_ctx or return;
  defined $ctx->{elem}
    ? $ctx->{elem}->{t}
    : '\'no element at current position\'';
}

sub _list_source {
  my $level = shift;
  my $ctx = _get_ctx($level) or return;
  my $src = $ctx->{text};
  my ($b, $e, $w) = ($ctx->{elem}{B}, $ctx->{elem}{E}, $ctx->{elem}{W});
  my $result = substr($$src, 0, $b)
    .  c_sprintf('%_cs', substr($$src, $b, $w));
  if ($e <= $ctx->{len}) {
    $result .= substr($$src, $e);
  }
  chomp $result;
  my @lines = split "\n", $result;
  my $depth = @{$P->{ctx}};
  my $margin = '> ';
  my $out_rows = 0;
  my $out_chars = 0;
  my $line_no = 0;
  my $footer_rows = 0;
  $margin x= $depth;
  for (@lines) {
    $line_no++;
    $out_chars += c_length($_) + length("\n");
    $footer_rows++ if $out_chars > $ctx->{elem}{E};
    my $line_no_fmt = $footer_rows == 1 ? '%_M4d %_Ms' : '%_m4d %_ms';
    my $prefix = c_sprintf $line_no_fmt, $line_no, $margin;
    my $line_len = c_length($_) + c_length($prefix) + length("\n");
    my $row_h = 1 + int(($line_len/$Cols)+.5);
    $out_rows += $row_h;
    print $OUT $prefix, $_, "\n";
    last if ($out_rows > $Rows && $footer_rows > int($Rows/2))
  }
}

sub _list_output {
  my $ctx = _get_ctx(@_);
  unless ($ctx) {
    my $out = ${$P->{out}};
    if ($out) { chomp $out; $out .= "\n"; } # ensure nl
    return c_printf '%_gs', $out;
  }
  my $out = ${$ctx->{out}} or return;
  my ($p, $e_p) = ($ctx->{pos}, $ctx->{elem}->{B});
  my $leader = $e_p > $p
    ? substr ${$ctx->{text}}, $p, $e_p - $p
    : '';
  chomp $out;
  c_printf '%_gs%_gs' . "\n", $out, $leader;
}

sub _stack_trace {
  my $level = @{$P->{ctx}};
  return unless $level;
  print $OUT "\n";
  for (@{$P->{ctx}}) {
    my $str = _prompt($level--, $_, 1);
    chomp $str;
    print $OUT "\t$str\n";
  }
  print $OUT "\n";
}

sub _dump_local_stack {
  my $scope = shift;
  # Stack variables
  my $i = 0;
  for ($i = @{$P->{stack}} - 1; $i >= 0; $i--) {
    $_ = $P->{stack}[$i];
    next if defined $scope && $scope ne $i;
    my $addr = $_->[1] || '';
    my $type = ref($_->[0]);
    c_printf "%_*s", "Local stack [$i] ($type) $addr\n";
    _print_var('%_gs', hf_format($_->[0], -ignore => ['Parse::Template::Content']));
  }
  c_printf "%_*s", "(empty stack)\n" if $i == 0;
}

# Context variables
sub _dump_context_vars {
  my $depth = defined $_[0] ? int(shift) : undef;
  my $dumper = sub {
    my ($depth, $ctx) = @_;
    my $vars = $ctx->{vars};
    # TODO - Instead of addr, create stack line (like the prompt and T trace)
    my $addr = join '/', grep defined, ($ctx->{path}, $ctx->{name});
    c_printf "%_*s", "Context variables [$depth] $addr\n";
    _print_var('%_gs', hf_format($vars, -ignore => ['Parse::Template::Content']));
  };
  my @ctx = @{$P->{ctx}} or return;
  my $len = @ctx;
  if (defined $depth) {
    my $i = $depth < 0 ? 0 : $len - $depth;
    if ($i > $#ctx || $i < 0) {
      c_printf "%_*s", "No context at depth: $depth\n";
      return;
    }
    &$dumper($len - $i, $ctx[$i]);
  } else {
    for (my $i = $#ctx; $i >= 0; $i--) {
      &$dumper($len - $i, $ctx[$i]);
    }
  }
}

sub _dump {
  unshift @_, _get_elem_text() unless @_;
  while (@_) {
    my $v = $P->get_value(str_ref(shift));
    _print_var('%_gs', ref $v ? hf_format $v : $v);
  }
}

sub _print {
  unshift @_, _get_elem_text() unless @_;
  while (@_) {
    my $v = $P->get_value_str(str_ref(shift));
    _print_var(q('%_gs'), $v);
  }
}

sub _print_var {
  my ($fmt, $v) = @_;
  if (defined $v) {
    chomp $v;
    c_printf $fmt."\n", $v;
  } else {
    c_printf '%_Rs'."\n", 'undef';
  }
}

# Util

sub _sig_warn(@) {
  my $msg = shift;
  print $OUT RED, $msg, RESET;
}

sub _sig_die(@) {
  my $msg = shift;
  print $OUT BOLD, RED, $msg, RESET;
  exit 1;
}

sub _qhelp {
  my %fmt = (
    br      => "\n",
    h1      => '%_Bs' . "\n",
    dt_dd   => '  %_^-15s %s' . "\n",
    indent  => '  %s' . "\n",
  );
  c_printf $fmt{h1},      'The prompt';
  c_printf $fmt{indent},  '1::/data(parse-me.txt:23/219) > ';
  c_printf $fmt{indent},  '|  |     |            |  |_____ Total chars';
  c_printf $fmt{indent},  '|  |     |            |________ Current char';
  c_printf $fmt{indent},  '|  |     |_____________________ Template name';
  c_printf $fmt{indent},  '|  |___________________________ Working dir';
  c_printf $fmt{indent},  '|______________________________ Depth';
  c_printf $fmt{h1},      'Commands';
  c_printf $fmt{dt_dd},   'ENTER',  'Repeat last n or s';
  c_printf $fmt{dt_dd},   'n', 'Next i.e., step over (default behavior)';
  c_printf $fmt{dt_dd},   's', 'Step i.e., step in';
  c_printf $fmt{dt_dd},   'r', 'Return i.e., step out';
  c_printf $fmt{dt_dd},   'l [num]', 'List source [at Depth]';
  c_printf $fmt{dt_dd},   'o [num]', 'List output [at Depth]';
  c_printf $fmt{dt_dd},   'p addr ...', 'Print value(s), e.g., p /sys/ENV/USER';
  c_printf $fmt{dt_dd},   'e|x addr ...', 'Examine values at address(es), e.g., x /sys/ENV';
  c_printf $fmt{dt_dd},   'c [num] ...', 'List context values [at parser depth]';
  c_printf $fmt{dt_dd},   'V [num]', 'List values [local value-stack depth]';
  c_printf $fmt{dt_dd},   'X', 'Same as "V 0" (list local values)';
  c_printf $fmt{dt_dd},   'C', 'Same as "c <current-depth>" (list current context values)';
  c_printf $fmt{dt_dd},   'T', 'Stack trace';
  c_printf $fmt{dt_dd},   'j', 'Toggle jump mode (minimal display)';
  c_printf $fmt{dt_dd},   '?|h', 'Quick help';
  c_printf $fmt{dt_dd},   'q', 'Quit';
}

1;

__END__
