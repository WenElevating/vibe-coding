'use strict';

function requireHighRiskApproval({ method, approvalPolicy }) {
  if (approvalPolicy && approvalPolicy.allowHighRiskForTests === true) return { decision: 'allow', source: 'test-policy' };
  const error = new Error(`Codex app-server method ${method} requires explicit approval`);
  error.status = 403;
  error.code = 'CODEX_APP_SERVER_APPROVAL_REQUIRED';
  error.recoverable = true;
  error.userAction = 'Approve this app-server operation before retrying.';
  throw error;
}

module.exports = { requireHighRiskApproval };
