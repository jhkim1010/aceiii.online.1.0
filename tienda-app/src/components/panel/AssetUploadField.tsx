import { useState } from 'react';
import type { CSSProperties } from 'react';
import { minioImageUrl, uploadThemeAsset } from '@/services/shop-api';
import type { ThemeAssetKind } from '@/services/shop-api';

const VIDEO_ERROR = 'El video supera 20MB o el formato no es válido (MP4/WEBM).';
const IMAGE_ERROR = 'El archivo supera 2MB o el formato no es válido (PNG/JPG/WEBP).';

export default function AssetUploadField({
  storeId,
  token,
  kind,
  value,
  onChange,
  label,
  accept,
}: {
  storeId: number;
  token: string;
  kind: ThemeAssetKind;
  value: string | null;
  onChange: (fileName: string | null) => void;
  label: string;
  accept: string;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hover, setHover] = useState(false);

  const onFile = async (file: File) => {
    setBusy(true);
    setError(null);
    try {
      const res = await uploadThemeAsset(storeId, token, file, kind);
      onChange(res.fileName);
    } catch {
      setError(kind === 'reelVideo' ? VIDEO_ERROR : IMAGE_ERROR);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div style={st.wrap}>
      <span style={st.label}>{label}</span>
      <label
        style={{ ...st.drop, ...(hover ? st.dropHover : null) }}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
      >
        <input
          type="file"
          accept={accept}
          style={st.hiddenInput}
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) onFile(file);
            e.target.value = '';
          }}
        />
        {busy ? 'Subiendo…' : '⬆ Subir archivo'}
      </label>
      {error ? <div style={st.error}>{error}</div> : null}
      {value ? (
        <div style={st.preview}>
          {kind === 'reelVideo' ? (
            <span style={st.fileName}>{value}</span>
          ) : (
            // SVG 는 반드시 <img> 로만 렌더한다 — 인라인 삽입 금지(T-61-40, XSS 방어)
            // eslint-disable-next-line @next/next/no-img-element
            <img src={minioImageUrl(value)} alt={label} style={st.img} />
          )}
          <button
            type="button"
            onClick={() => onChange(null)}
            style={st.removeBtn}
          >
            Quitar
          </button>
        </div>
      ) : null}
    </div>
  );
}

const st: Record<string, CSSProperties> = {
  wrap: { display: 'flex', flexDirection: 'column', gap: 4 },
  label: { fontSize: 11, color: '#9aa2b1', display: 'block' },
  drop: {
    border: '1px dashed #32325a',
    borderRadius: 8,
    padding: 16,
    textAlign: 'center',
    cursor: 'pointer',
    color: '#9aa2b1',
    fontSize: 11,
    display: 'block',
  },
  dropHover: { borderColor: '#f5a623', color: '#f5a623' },
  hiddenInput: { display: 'none' },
  error: { fontSize: 11, color: '#f7c471' },
  preview: { display: 'flex', alignItems: 'center', gap: 8, marginTop: 4 },
  img: { maxHeight: 48, objectFit: 'contain' },
  fileName: { fontSize: 11, color: '#e8eaed', flex: 1, wordBreak: 'break-all' },
  removeBtn: {
    background: 'transparent',
    border: 0,
    color: '#9aa2b1',
    cursor: 'pointer',
    fontSize: 11,
    textDecoration: 'underline',
  },
};
