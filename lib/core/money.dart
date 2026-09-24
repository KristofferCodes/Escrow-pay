/// Lamport arithmetic and display.
///
/// Amounts are held as `int` lamports everywhere except the input field and
/// the labels the user reads. Doing the conversion in exactly one place keeps
/// rounding errors out of anything that gets signed.
abstract final class Money {
  static const lamportsPerSol = 1000000000;

  /// Parses user input in SOL into lamports. Returns `null` when the text is
  /// not a positive, representable amount.
  static int? solToLamports(String input) {
    final text = input.trim().replaceAll(',', '');
    if (text.isEmpty) return null;

    final sol = double.tryParse(text);
    if (sol == null || sol <= 0 || !sol.isFinite) return null;

    // Round rather than truncate so 0.1 does not become 99999999 lamports.
    final lamports = (sol * lamportsPerSol).round();
    return lamports > 0 ? lamports : null;
  }

  /// Formats lamports as SOL, trimming trailing zeros but never the leading
  /// digit: `1.5`, `0.001`, `2`.
  static String solLabel(int lamports, {int maxDecimals = 9}) {
    final whole = lamports ~/ lamportsPerSol;
    final fraction = lamports.remainder(lamportsPerSol).abs();
    if (fraction == 0) return '$whole';

    var digits = fraction.toString().padLeft(9, '0');
    if (maxDecimals < 9) digits = digits.substring(0, maxDecimals);
    digits = digits.replaceFirst(RegExp(r'0+$'), '');

    return digits.isEmpty ? '$whole' : '$whole.$digits';
  }

  /// `1.5 SOL`
  static String sol(int lamports) => '${solLabel(lamports)} SOL';

  /// Shortens an address for display while keeping enough of both ends to be
  /// verifiable against a wallet screen.
  static String shortAddress(String address, {int edge = 4}) {
    if (address.length <= edge * 2 + 1) return address;
    return '${address.substring(0, edge)}…${address.substring(address.length - edge)}';
  }
}
