import { useState } from 'react';
import type { CSSProperties, ReactNode } from 'react';

// 표면 A(에디터 크롬) 전용 재사용 부품 — 고정 Ventago 다크 네이비+골드 팔레트.
// 매장 테마(표면 B)와 무관, var(--*) CSS 변수를 쓰지 않고 리터럴 hex 를 그대로 쓴다
// (UI-SPEC "표면 A는 고정 팔레트" 규칙).

export function AccordionGroup({
  icon,
  title,
  defaultOpen,
  children,
}: {
  icon: string;
  title: string;
  defaultOpen?: boolean;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen === true);
  const [hover, setHover] = useState(false);

  return (
    <div style={st.group}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
        aria-expanded={open}
        style={{ ...st.header, background: hover ? '#262649' : '#20203c' }}
      >
        <span>
          {icon} {title}
        </span>
        <span
          style={{
            marginLeft: 'auto',
            color: '#9aa2b1',
            transition: 'transform .2s',
            transform: open ? 'rotate(90deg)' : 'none',
          }}
        >
          ›
        </span>
      </button>
      {open ? <div style={st.body}>{children}</div> : null}
    </div>
  );
}

export function TextField({
  label,
  value,
  onChange,
  placeholder,
  maxLength = 200,
  multiline,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  maxLength?: number;
  multiline?: boolean;
}) {
  return (
    <label style={st.field}>
      <span style={st.label}>{label}</span>
      {multiline ? (
        <textarea
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          maxLength={maxLength}
          rows={3}
          style={st.input}
        />
      ) : (
        <input
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          maxLength={maxLength}
          style={st.input}
        />
      )}
    </label>
  );
}

export function NumberField({
  label,
  value,
  onChange,
  min,
  max,
  step,
}: {
  label: string;
  value: number;
  onChange: (v: number) => void;
  min?: number;
  max?: number;
  step?: number;
}) {
  return (
    <label style={st.field}>
      <span style={st.label}>{label}</span>
      <input
        type="number"
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        min={min}
        max={max}
        step={step}
        style={st.input}
      />
    </label>
  );
}

export function SelectField({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <label style={st.field}>
      <span style={st.label}>{label}</span>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        style={st.input}
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </label>
  );
}

export function SwitchField({
  label,
  checked,
  onChange,
  hint,
}: {
  label: string;
  checked: boolean;
  onChange: (v: boolean) => void;
  hint?: string;
}) {
  return (
    <div>
      <div style={st.switchRow}>
        <span style={st.switchLabel}>{label}</span>
        <label style={st.switchTrackWrap}>
          <input
            type="checkbox"
            checked={checked}
            onChange={(e) => onChange(e.target.checked)}
            style={st.switchInput}
          />
          <span
            style={{
              ...st.switchTrack,
              background: checked ? '#f5a623' : '#32325a',
            }}
          >
            <span
              style={{
                ...st.switchKnob,
                transform: checked ? 'translateX(12px)' : 'none',
              }}
            />
          </span>
        </label>
      </div>
      {hint ? <div style={st.hintText}>{hint}</div> : null}
    </div>
  );
}

export function HintBanner({ children }: { children: ReactNode }) {
  return <div style={st.hintBanner}>{children}</div>;
}

export function WarnBanner({ children }: { children: ReactNode }) {
  return <div style={st.warnBanner}>{children}</div>;
}

const st: Record<string, CSSProperties> = {
  group: {
    borderRadius: 10,
    marginBottom: 8,
    overflow: 'hidden',
  },
  header: {
    width: '100%',
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    border: '1px solid #32325a',
    borderRadius: 8,
    padding: '12px',
    color: '#e8eaed',
    fontSize: 13.5,
    fontWeight: 700,
    cursor: 'pointer',
    textAlign: 'left',
  },
  body: {
    padding: '12px',
    display: 'flex',
    flexDirection: 'column',
    gap: 12,
  },
  field: { display: 'flex', flexDirection: 'column' },
  label: { fontSize: 11, color: '#9aa2b1', marginBottom: 4, display: 'block' },
  input: {
    width: '100%',
    background: '#1a1a2e',
    color: '#e8eaed',
    border: '1px solid #32325a',
    borderRadius: 8,
    padding: '8px 12px',
    fontSize: 13,
  },
  switchRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
    fontSize: 13,
    color: '#e8eaed',
  },
  switchLabel: { flex: 1 },
  switchTrackWrap: {
    position: 'relative',
    width: 28,
    height: 16,
    flexShrink: 0,
    cursor: 'pointer',
  },
  switchInput: {
    opacity: 0,
    position: 'absolute',
    width: '100%',
    height: '100%',
    margin: 0,
    cursor: 'pointer',
  },
  switchTrack: {
    position: 'absolute',
    inset: 0,
    borderRadius: 20,
    transition: '.2s',
    pointerEvents: 'none',
  },
  switchKnob: {
    position: 'absolute',
    width: 12,
    height: 12,
    borderRadius: '50%',
    background: '#fff',
    top: 2,
    left: 2,
    transition: '.2s',
  },
  hintText: { fontSize: 11, color: '#9aa2b1', marginTop: 4 },
  hintBanner: {
    background: '#22d3ee12',
    border: '1px solid #22d3ee33',
    borderRadius: 8,
    padding: '8px 12px',
    color: '#a5e9f5',
    fontSize: 11,
    lineHeight: 1.5,
    marginTop: 12,
  },
  warnBanner: {
    background: '#f5a62312',
    border: '1px solid #f5a62333',
    borderRadius: 8,
    padding: '8px 12px',
    color: '#f7c471',
    fontSize: 11,
    lineHeight: 1.5,
    marginTop: 12,
  },
};
