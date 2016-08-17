package App::Console::Prompts;
use strict;
use Exporter qw(import);
use Perl::Module;
use Digest::SHA1;
our $VERSION = 0.1;
our @EXPORT = qw();
our @EXPORT_OK = qw(prompt prompt_for_password prompt_Yn prompt_yN prompt_yn);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);

our $Out = \*STDERR;
our $In = \*STDIN;

# ------------------------------------------------------------------------------
# prompt - Prompt for input
# prompt $question
# prompt $question, $default
#
# options:
# 
#   -nocolon  Do not put a colon (:) at the end of the prompt
#   -noecho   Do not echo typed characters
#   -noempty  Reprompt if no input is received
# ------------------------------------------------------------------------------

sub prompt {
  my $opts = my_opts(\@_);
  my $p = shift || '';
  my $default = shift;
  my $r;
  my $suffix = ($$opts{nocolon} || $p =~ /[\?:\!]$/s) ? ' ' : ': ';
  print $Out "$p$suffix";
  $default and print $Out "[$default] ";
  $opts->{noecho} and system("stty -echo");
  $r = <$In>;
  if ($opts->{noecho}) {
    system("stty echo");
    print $Out "\n";
  }
  chomp $r;
  $r eq '' && defined $default and $r = $default;
  $r = prompt($p, $default, -opts => $opts) if $r eq '' && $$opts{noempty};
  $r;
}
1;

# ------------------------------------------------------------------------------
# prompt_for_password - Prompt for input
# prompt_for_password
# prompt_for_password $text
#
# options:
# 
#   -noempty  Require non-empty passwords
#   -confirm  Require confirmation
#   -sha1hex  Digest the password before returning
# ------------------------------------------------------------------------------

sub prompt_for_password {
  my $opts = my_opts(\@_, {
    noempty => 0,
    confirm => 0,
    sha1hex => 0,
  });

  my $txt = shift || 'Password';
  my $strlen = length($txt) > length('again') ? length($txt) : 5;
  my $is_valid = 0;
  my $pw1;

  while (!$is_valid) {
    $pw1 = prompt(sprintf("%${strlen}s", $txt), -noecho);
    $pw1 = '' unless defined $pw1;
    if ($$opts{'noempty'} && $pw1 eq '') {
      print $Out "Passwords may not be empty\n";
      next;
    }

    if ($$opts{'confirm'}) {
      my $pw2 = prompt(sprintf("%${strlen}s", 'again'), -noecho);
      $pw2 = '' unless defined $pw2;
      if ($pw1 ne $pw2) {
        print $Out "Passwords do not match\n";
        next;
      }
    }

    $is_valid = 1;
  }

  return Digest::SHA1::sha1_hex($pw1) if $$opts{'sha1hex'};
  return $pw1;
}

# ------------------------------------------------------------------------------
# prompt_yn - Prompt for a yes/no response (require an answer)
# prompt_yn $question
# ------------------------------------------------------------------------------

sub prompt_yn {_prompt_yn(shift, 'yn');}

# ------------------------------------------------------------------------------
# prompt_Yn - Prompt for a yes/no response (default is Yes)
# prompt_Yn $question
# ------------------------------------------------------------------------------

sub prompt_Yn {_prompt_yn(shift, 'Yn');}

# ------------------------------------------------------------------------------
# prompt_yN - Prompt for a yes/no response (default is No)
# prompt_yN $question
# ------------------------------------------------------------------------------

sub prompt_yN {_prompt_yn(shift, 'yN');}

# ------------------------------------------------------------------------------
# _prompt_yn - Prompt for a yes/no response
# _prompt_yn $question
# _prompt_yn $question, $type
#
# C<$type>:
#
#   'yN'    Default is no (default)
#   'Yn'    Default is yes
#   'yn'    Require input
# ------------------------------------------------------------------------------

sub _prompt_yn {
  my $txt = shift || '';
  my $type = shift || 'yN';
  $txt .= $type eq 'yN' ? ' [yN]' :
          $type eq 'Yn' ? ' [Yn]' :
          $type eq 'yn' ? ' [yn]' :
          '';
  my $yn = prompt($txt);
  if (!defined($yn) || $yn eq '') {
    $yn = prompt($txt, $type) if $type !~ /[YN]/;
    $yn = index($type, 'Y') >= 0 ? 'y' : 'n';
  }
  return $yn =~ /^y/i ? 1 : 0;
}

__END__

=pod:synopsis

  use App::Console::Prompts qw(:all);
  my $color = prompt('What's your favorite color?');
  my $pw = prompt_for_password();

=pod:description

  Prompt to STDERR and read from STDIN.

=cut
