// git-errors.mts — turn git's refusals into a message that says what to do. GitHub answers an
// unauthenticated request for a private repo with "Repository not found" (HTTPS) or
// "Permission denied (publickey)" (SSH), neither of which mentions credentials; an org that
// enforces SAML SSO refuses a valid token until it is authorised for the org in the browser.
const AUTH_PATTERNS = [
  /permission denied \(publickey\)/i,
  /repository not found/i,
  /could not read username/i,
  /authentication failed/i,
  /invalid username or token/i,
  /host key verification failed/i,
  /could not read from remote repository/i,
];

const SAML_PATTERN = /SAML SSO/i;

export const SSO_HINT =
  "Open https://github.com/settings/tokens, pick the token, 'Configure SSO' → Authorize the organisation, then rerun this command.";

export function isSamlBlocked(gitOutput: string): boolean {
  return SAML_PATTERN.test(gitOutput);
}

export function isAuthFailure(gitOutput: string): boolean {
  return AUTH_PATTERNS.some((pattern) => pattern.test(gitOutput));
}

export function explainCloneFailure(url: string, gitOutput: string): string {
  const output = gitOutput.trim();
  if (isSamlBlocked(output)) {
    return [
      `cannot clone ${url}: the token is not authorised for the organisation's SAML SSO.`,
      output,
      "",
      SSO_HINT,
    ].join("\n");
  }
  if (!isAuthFailure(output)) return `git clone ${url} failed:\n${output}`;
  return [
    `cannot clone ${url}: GitHub refused the credentials on this machine.`,
    output,
    "",
    "Private repos need a GitHub token (a PAT with the 'repo' scope, SSO-authorised for the org):",
    "  put it in ~/.config/skoolscout/secrets.env as GITHUB_TOKEN, then",
    "  ./install.sh --only github-auth   # gh login + git over HTTPS with that token",
    "  gh auth login --git-protocol https  # or log in without a PAT, then the same step",
    "then rerun this command.",
  ].join("\n");
}
