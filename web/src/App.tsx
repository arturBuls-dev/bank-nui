import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { callApi, devAccount } from './api';
import { fetchNui, isInGame, useNuiEvent } from './nui';
import type { Account, HistoryRow, Result } from './types';

type OpenMessage = { action: 'open'; data: Account };
type Tab = 'deposit' | 'withdraw' | 'transfer';
type Notice = { type: 'ok' | 'error'; text: string };

const money = (n: number) => `$${n.toLocaleString('en-US')}`;

const KIND: Record<HistoryRow['kind'], { label: string; sign: 1 | -1 }> = {
  deposit: { label: 'Deposit', sign: 1 },
  withdraw: { label: 'Withdrawal', sign: -1 },
  transfer_in: { label: 'Received from', sign: 1 },
  transfer_out: { label: 'Sent to', sign: -1 },
};

const TABS: { id: Tab; label: string }[] = [
  { id: 'deposit', label: 'Deposit' },
  { id: 'withdraw', label: 'Withdraw' },
  { id: 'transfer', label: 'Transfer' },
];

const timeAgo = (unix: number) => {
  const s = Math.max(0, Math.floor(Date.now() / 1000) - unix);
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  return `${Math.floor(s / 86400)} d ago`;
};

export default function App() {
  // In a browser (development mode) show the window right away with sample data
  const [visible, setVisible] = useState(!isInGame());
  const [account, setAccount] = useState<Account | null>(isInGame() ? null : devAccount());
  const [tab, setTab] = useState<Tab>('deposit');
  const [amount, setAmount] = useState('');
  const [target, setTarget] = useState('');
  const [notice, setNotice] = useState<Notice | null>(null);
  const [busy, setBusy] = useState(false);

  useNuiEvent<OpenMessage>('open', useCallback((msg) => {
    setAccount(msg.data);
    setAmount('');
    setTarget('');
    setNotice(null);
    setTab('deposit');
    setVisible(true);
  }, []));

  const close = useCallback(() => {
    setVisible(false);
    fetchNui('close');
  }, []);

  // Escape closes the window
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && visible) close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [visible, close]);

  if (!visible || !account) {
    return isInGame() ? null : (
      <button className="dev-open" onClick={() => { setAccount(devAccount()); setVisible(true); }}>
        Open ATM (dev)
      </button>
    );
  }

  const max = tab === 'transfer' ? account.limits.maxTransfer : account.limits.maxAmount;
  const source = tab === 'deposit' ? account.cash : account.bank;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const value = Math.floor(Number(amount));
    if (!Number.isFinite(value) || value < 1) {
      setNotice({ type: 'error', text: 'Enter a whole amount.' });
      return;
    }
    if (tab === 'transfer' && target.trim().length < 3) {
      setNotice({ type: 'error', text: 'Enter an account number.' });
      return;
    }

    setBusy(true);
    // The server checks everything again, this is only a friendly early check
    const result: Result = await callApi(tab, { amount: value, target: target.trim() });
    setBusy(false);

    if (result.ok) {
      setAccount(result.data);
      setAmount('');
      setNotice({
        type: 'ok',
        text: tab === 'deposit' ? `Deposited ${money(value)}.` : tab === 'withdraw' ? `Withdrew ${money(value)}.` : `Sent ${money(value)}.`,
      });
    } else {
      setNotice({ type: 'error', text: result.error });
    }
  };

  const quick = (value: number) => setAmount(String(Math.min(value, max)));

  return (
    <div className="atm">
      <header className="atm-head">
        <div>
          <span className="eyebrow">{account.bankName}</span>
          <h1>{account.name}</h1>
          <p className="acct">
            Account <b>{account.id}</b>
          </p>
        </div>
        <button className="close" onClick={close} aria-label="Close">×</button>
      </header>

      <div className="balances">
        <div className="bal main">
          <span className="bal-label">Bank</span>
          <span className="bal-value">{money(account.bank)}</span>
        </div>
        <div className="bal">
          <span className="bal-label">Cash</span>
          <span className="bal-value">{money(account.cash)}</span>
        </div>
      </div>

      <div className="tabs" role="tablist">
        {TABS.map((t) => (
          <button
            key={t.id}
            role="tab"
            aria-selected={tab === t.id}
            className={`tab${tab === t.id ? ' on' : ''}`}
            onClick={() => { setTab(t.id); setNotice(null); }}
          >
            {t.label}
          </button>
        ))}
      </div>

      <form className="panel" onSubmit={submit}>
        {tab === 'transfer' && (
          <label className="field-row">
            <span>Account number</span>
            <input
              value={target}
              onChange={(e) => setTarget(e.target.value)}
              placeholder="e.g. ABC12345"
              maxLength={20}
              autoComplete="off"
            />
          </label>
        )}

        <label className="field-row">
          <span>Amount {tab === 'deposit' ? '(from cash)' : '(from bank)'}</span>
          <input
            inputMode="numeric"
            value={amount}
            onChange={(e) => setAmount(e.target.value.replace(/[^0-9]/g, ''))}
            placeholder="0"
            autoComplete="off"
          />
        </label>

        <div className="chips">
          {[100, 500, 1000, 5000].map((v) => (
            <button type="button" key={v} className="chip" onClick={() => quick(v)}>
              {money(v)}
            </button>
          ))}
          <button type="button" className="chip" onClick={() => quick(source)}>
            All
          </button>
        </div>

        {notice && <p className={`notice ${notice.type}`}>{notice.text}</p>}

        <button className="submit" type="submit" disabled={busy}>
          {tab === 'deposit' ? 'Deposit' : tab === 'withdraw' ? 'Withdraw' : 'Send money'}
        </button>
      </form>

      <section className="history">
        <h2>Recent activity</h2>
        {account.history.length === 0 ? (
          <p className="empty">No transactions yet.</p>
        ) : (
          <ul>
            {account.history.map((row, i) => {
              const k = KIND[row.kind];
              return (
                <li key={`${row.at}-${i}`}>
                  <span className={`dot ${k.sign > 0 ? 'in' : 'out'}`} />
                  <span className="what">
                    {k.label}
                    {row.counterparty ? ` ${row.counterparty}` : ''}
                    <small>{timeAgo(row.at)}</small>
                  </span>
                  <span className={`amt ${k.sign > 0 ? 'in' : 'out'}`}>
                    {k.sign > 0 ? '+' : '-'}
                    {money(row.amount)}
                  </span>
                </li>
              );
            })}
          </ul>
        )}
      </section>
    </div>
  );
}
