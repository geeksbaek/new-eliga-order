import { useCallback, useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ErrorBox, InfoBox } from '../components/UiState'
import { PageHeader } from '../components/PageHeader'
import {
  MEAL_SLOTS,
  TIME_PRESETS,
  anyMealNotifyEnabled,
  loadNotificationPrefs,
  normalizeTime,
  notificationPermission,
  notifyMealSlot,
  requestNotificationPermission,
  saveNotificationPrefs,
  type MealSlot,
  type NotificationPrefs,
} from '../lib/meal-notify'
import { CAFETERIA_SHOP_ID } from '../lib/shop-rules'
import { useShop } from '../hooks/useShop'
import { isCafeteriaShop } from '../lib/shop-rules'
import { useAuth } from '../hooks/useAuth'
import {
  loadTextSize,
  saveTextSize,
  type TextSize,
} from '../lib/text-size'

function permissionLabel(p: NotificationPermission | 'unsupported'): string {
  switch (p) {
    case 'granted':
      return '허용됨'
    case 'denied':
      return '차단됨'
    case 'default':
      return '아직 요청하지 않음'
    case 'unsupported':
      return '이 브라우저는 알림을 지원하지 않습니다'
    default:
      return String(p)
  }
}

export function SettingsPage() {
  const navigate = useNavigate()
  const { userId, logout } = useAuth()
  const { shops } = useShop()
  const [prefs, setPrefs] = useState<NotificationPrefs>(() =>
    loadNotificationPrefs(),
  )
  const [perm, setPerm] = useState<NotificationPermission | 'unsupported'>(() =>
    notificationPermission(),
  )
  const [testBusy, setTestBusy] = useState<MealSlot | null>(null)
  const [testMsg, setTestMsg] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [textSize, setTextSize] = useState<TextSize>(() => loadTextSize())

  const diningShops = useMemo(() => {
    const live = shops.filter(
      (s) => isCafeteriaShop(s.type) || s.shopId === CAFETERIA_SHOP_ID,
    )
    if (live.length > 0) return live
    return [{ shopId: CAFETERIA_SHOP_ID, name: '춘식도락(B1F)', type: 'CAFETERIA' as const }]
  }, [shops])

  const refreshPerm = useCallback(() => {
    setPerm(notificationPermission())
  }, [])

  useEffect(() => {
    refreshPerm()
  }, [refreshPerm])

  function commit(next: NotificationPrefs) {
    setPrefs(next)
    saveNotificationPrefs(next)
  }

  function patchMeal(
    slot: MealSlot,
    patch: Partial<NotificationPrefs['meals'][MealSlot]>,
  ) {
    commit({
      ...prefs,
      meals: {
        ...prefs.meals,
        [slot]: { ...prefs.meals[slot], ...patch },
      },
    })
  }

  async function enablePermission() {
    setError(null)
    setTestMsg(null)
    const result = await requestNotificationPermission()
    setPerm(result)
    if (result === 'denied') {
      setError(
        '브라우저에서 알림이 차단되어 있습니다. 사이트 설정에서 알림을 허용해 주세요.',
      )
    } else if (result === 'unsupported') {
      setError('이 환경에서는 브라우저 알림을 쓸 수 없습니다.')
    }
  }

  async function onToggle(slot: MealSlot, enabled: boolean) {
    setError(null)
    setTestMsg(null)
    if (enabled && notificationPermission() !== 'granted') {
      const result = await requestNotificationPermission()
      setPerm(result)
      if (result !== 'granted') {
        setError(
          result === 'denied'
            ? '알림 권한이 없어 켤 수 없습니다. 브라우저 설정에서 허용해 주세요.'
            : '알림 권한을 허용해야 식단 알림을 받을 수 있습니다.',
        )
        return
      }
    }
    patchMeal(slot, { enabled })
  }

  async function sendTest(slot: MealSlot) {
    setError(null)
    setTestMsg(null)
    setTestBusy(slot)
    try {
      if (notificationPermission() !== 'granted') {
        const result = await requestNotificationPermission()
        setPerm(result)
        if (result !== 'granted') {
          setError('알림 권한이 필요합니다.')
          return
        }
      }
      const r = await notifyMealSlot(slot, { force: true, prefs })
      if (r.ok) {
        setTestMsg('알림을 보냈습니다. 기기 알림함을 확인해 보세요.')
      } else if (r.reason === 'permission') {
        setError('알림 권한이 없습니다.')
      } else {
        setTestMsg('알림 전송을 시도했습니다. 메뉴가 없으면 안내 문구가 갑니다.')
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : '알림을 보내지 못했습니다')
    } finally {
      setTestBusy(null)
    }
  }

  const enabledCount = MEAL_SLOTS.filter((s) => prefs.meals[s.id].enabled).length

  return (
    <div className="settings-page">
      <PageHeader
        back={{ fallbackTo: '/', label: '홈' }}
        title="설정"
        sub="식단 알림과 화면 표시를 조정합니다."
      />

      <section className="settings-card" aria-labelledby="text-size-title">
        <div className="settings-card-head">
          <h2 id="text-size-title" className="settings-card-title">
            글자 크기
          </h2>
          <span className="settings-pill">
            {textSize === 'large' ? '크게' : '보통'}
          </span>
        </div>
        <p className="settings-card-desc">
          앱 전체 글자 크기입니다. 지금 크기가 보통입니다.
        </p>
        <div
          className="segment segment-2 settings-text-size"
          role="radiogroup"
          aria-label="글자 크기"
        >
          <button
            type="button"
            role="radio"
            aria-checked={textSize === 'normal'}
            className={`segment-item${textSize === 'normal' ? ' is-active' : ''}`}
            onClick={() => {
              setTextSize('normal')
              saveTextSize('normal')
            }}
          >
            <span className="segment-label">보통</span>
          </button>
          <button
            type="button"
            role="radio"
            aria-checked={textSize === 'large'}
            className={`segment-item${textSize === 'large' ? ' is-active' : ''}`}
            onClick={() => {
              setTextSize('large')
              saveTextSize('large')
            }}
          >
            <span className="segment-label">크게</span>
          </button>
        </div>
      </section>

      <section className="settings-card" aria-labelledby="notify-perm-title">
        <div className="settings-card-head">
          <h2 id="notify-perm-title" className="settings-card-title">
            알림 권한
          </h2>
          <span
            className={`settings-pill${perm === 'granted' ? ' is-ok' : perm === 'denied' ? ' is-bad' : ''}`}
          >
            {permissionLabel(perm)}
          </span>
        </div>
        <p className="settings-card-desc">
          앱이 열려 있거나 최근에 사용한 경우 설정 시각에 메뉴 알림이 울립니다.
          완전 종료 상태에서는 브라우저·OS 정책에 따라 전달되지 않을 수 있습니다.
        </p>
        {perm !== 'granted' && perm !== 'unsupported' && (
          <button
            type="button"
            className="btn btn-primary settings-perm-btn"
            onClick={() => void enablePermission()}
          >
            알림 허용하기
          </button>
        )}
      </section>

      <section className="settings-card" aria-labelledby="notify-meals-title">
        <div className="settings-card-head">
          <h2 id="notify-meals-title" className="settings-card-title">
            식단 알림
          </h2>
          <span className="settings-pill">
            {enabledCount > 0 ? `${enabledCount}개 켜짐` : '꺼짐'}
          </span>
        </div>

        <label className="settings-field">
          <span className="settings-field-label">식당</span>
          <select
            className="settings-select"
            value={prefs.shopId}
            onChange={(e) =>
              commit({ ...prefs, shopId: Number(e.target.value) })
            }
          >
            {diningShops.map((s) => (
              <option key={s.shopId} value={s.shopId}>
                {s.name}
              </option>
            ))}
          </select>
        </label>

        <ul className="settings-meal-list">
          {MEAL_SLOTS.map((slot) => {
            const meal = prefs.meals[slot.id]
            const presets = TIME_PRESETS.filter((t) => {
              const h = Number(t.slice(0, 2))
              if (slot.id === 'breakfast') return h >= 6 && h <= 9
              if (slot.id === 'lunch') return h >= 10 && h <= 12
              return h >= 16 && h <= 19
            })
            return (
              <li key={slot.id} className="settings-meal">
                <div className="settings-meal-row">
                  <div className="settings-meal-text">
                    <strong>{slot.label} 알림</strong>
                    <span className="settings-meal-hint">
                      {meal.enabled
                        ? `매일 ${meal.time} · 메뉴 전송`
                        : '꺼져 있음'}
                    </span>
                  </div>
                  <button
                    type="button"
                    role="switch"
                    aria-checked={meal.enabled}
                    aria-label={`${slot.label} 알림`}
                    className={`settings-switch${meal.enabled ? ' is-on' : ''}`}
                    onClick={() => void onToggle(slot.id, !meal.enabled)}
                  >
                    <span className="settings-switch-knob" />
                  </button>
                </div>

                <div
                  className={`settings-meal-body${meal.enabled ? '' : ' is-dim'}`}
                >
                  <label className="settings-field settings-field-inline">
                    <span className="settings-field-label">알림 시각</span>
                    <input
                      type="time"
                      className="settings-time"
                      value={meal.time}
                      disabled={!meal.enabled}
                      onChange={(e) =>
                        patchMeal(slot.id, {
                          time: normalizeTime(e.target.value || slot.defaultTime),
                        })
                      }
                    />
                  </label>
                  <div className="settings-presets" role="group" aria-label="자주 쓰는 시각">
                    {presets.map((t) => (
                      <button
                        key={t}
                        type="button"
                        className={`settings-chip${meal.time === t ? ' is-active' : ''}`}
                        disabled={!meal.enabled}
                        onClick={() => patchMeal(slot.id, { time: t })}
                      >
                        {t}
                      </button>
                    ))}
                  </div>
                  <button
                    type="button"
                    className="btn btn-ghost settings-test-btn"
                    disabled={testBusy != null}
                    onClick={() => void sendTest(slot.id)}
                  >
                    {testBusy === slot.id
                      ? '보내는 중…'
                      : `${slot.label} 메뉴 미리 받기`}
                  </button>
                </div>
              </li>
            )
          })}
        </ul>
      </section>

      {error && <ErrorBox>{error}</ErrorBox>}
      {testMsg && <InfoBox>{testMsg}</InfoBox>}

      <p className="settings-footnote">
        {anyMealNotifyEnabled(prefs)
          ? '알림은 하루에 식사 종류마다 한 번만 보냅니다. 시각 이후 약 15분 안에 앱이 실행 중이면 발송됩니다.'
          : '원하는 식사 알림을 켜 보세요. 기본 시각은 중식 10:40, 석식 17:00입니다.'}
      </p>

      <section
        className="settings-card settings-card-account"
        aria-labelledby="account-title"
      >
        <div className="settings-card-head">
          <h2 id="account-title" className="settings-card-title">
            계정
          </h2>
        </div>
        {userId ? (
          <p className="settings-card-desc settings-account-id">{userId}</p>
        ) : null}
        <button
          type="button"
          className="btn btn-ghost btn-block settings-logout-btn"
          onClick={() => {
            logout()
            navigate('/login', { replace: true })
          }}
        >
          로그아웃
        </button>
      </section>
    </div>
  )
}
