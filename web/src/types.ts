export type Kind = 'deposit' | 'withdraw' | 'transfer_in' | 'transfer_out';

export type HistoryRow = {
  kind: Kind;
  amount: number;
  counterparty: string | null;
  balanceAfter: number;
  at: number; // unix seconds
};

export type Account = {
  bankName: string;
  id: string;
  name: string;
  cash: number;
  bank: number;
  history: HistoryRow[];
  limits: { maxAmount: number; maxTransfer: number };
};

export type Result = { ok: true; data: Account } | { ok: false; error: string };
