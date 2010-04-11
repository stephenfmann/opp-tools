# Chi-square probability combining and related constants.
# package Mail::SpamAssassin::Bayes::CombineChi; 1;

package classifier::CombineChi;
use strict;
use warnings;
use bytes;
use POSIX qw(frexp);
use constant LN2 => log(2);

# Value for 'x' in Gary Robinson's f(w) equation.
# "Let x = the number used when n [hits] is 0."
our $FW_X_CONSTANT = 0.538;

# Value for 's' in the f(w) equation.  "We can see s as the "strength" (hence
# the use of "s") of an original assumed expectation ... relative to how
# strongly we want to consider our actual collected data."  Low 's' means
# trust collected data more strongly.
our $FW_S_CONSTANT = 0.030;

# (s . x) for the f(w) equation.
our $FW_S_DOT_X = ($FW_X_CONSTANT * $FW_S_CONSTANT);

# Should we ignore tokens with probs very close to the middle ground (.5)?
# tokens need to be outside the [ .5-MPS, .5+MPS ] range to be used.
our $MIN_PROB_STRENGTH = 0.346;

###########################################################################

# Chi-Squared method. Produces mostly boolean $result,
# but with a grey area.
sub combine {
  my ($ns, $nn, $sortedref) = @_;

  # @$sortedref contains an array of the probabilities
  my $wc = scalar @$sortedref;
  return unless $wc;

  my ($H, $S);
  my ($Hexp, $Sexp);
  $Hexp = $Sexp = 0;

  # see bug 3118
  my $totmsgs = ($ns + $nn);
  if ($totmsgs == 0) { return; }
  $S = ($ns / $totmsgs);
  $H = ($nn / $totmsgs);

  foreach my $prob (@$sortedref) {
    $S *= 1.0 - $prob;
    $H *= $prob;
    if ($S < 1e-200) {
      my $e;
      ($S, $e) = frexp($S);
      $Sexp += $e;
    }
    if ($H < 1e-200) {
      my $e;
      ($H, $e) = frexp($H);
      $Hexp += $e;
    }
  }

  $S = log($S) + $Sexp * LN2;
  $H = log($H) + $Hexp * LN2;

  # note: previous versions used (2 * $wc) as second arg ($v), but the chi2q()
  # fn then just used ($v/2) internally!  changed to simply supply $wc as
  # ($halfv) directly instead to avoid redundant doubling and halving.  The
  # side-effect is that chi2q() uses a different API now, but it's only used
  # here anyway.

  $S = 1.0 - chi2q(-2.0 * $S, $wc);
  $H = 1.0 - chi2q(-2.0 * $H, $wc);
  return (($S - $H) + 1.0) / 2.0;
}

# Chi-squared function (API changed; see comment above)
sub chi2q {
  my ($x2, $halfv) = @_;    

  my $m = $x2 / 2.0;
  my ($sum, $term);
  $sum = $term = exp(0 - $m);
  
  # replace 'for my $i (1 .. (($v/2)-1))' idiom, which creates a temp
  # array, with a plain C-style for loop
  my $i;
  for ($i = 1; $i < $halfv; $i++) {
    $term *= $m / $i;
    $sum += $term;
  }
  return $sum < 1.0 ? $sum : 1.0;
}

1;
