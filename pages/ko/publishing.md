## 패키지 레지스트리

**packages.nabi-lang.org**는 Nabi 패키지 레지스트리입니다. 여기의 패키지는 루트에 `nabi.nabion`이 있고 `src/`에 소스가 있는 git 저장소 하나입니다. 레지스트리의 데이터는 git 저장소 하나, 곧 [index](https://github.com/nabi-lang/packages-index)가 전부입니다. 각 버전은 패키지 저장소의 커밋 하나를 가리키고, 레지스트리는 그 커밋의 보관본을 둡니다. `nabi`는 그 보관본을 내려받아 index와 맞는지 확인합니다. 줄의 형식은 [index README](https://github.com/nabi-lang/packages-index#readme)에 있습니다.

패키지를 쓰고 공개하는 가이드는 Nabi 문서에 있습니다. 이 페이지는 그 요약입니다.

## 패키지 사용

```sh
nabi add json            # 최신 버전과 호환되는 범위 (^0.1.0)
nabi add http@^0.1       # 범위를 직접 지정
```

`nabi add`는 `nabi.nabion`의 `deps`에 한 줄을 씁니다. 다음 `nabi build`는 범위 안에서 가장 높은 버전을 고르고(철회된 버전은 건너뜁니다) `nabi.lock`에 고정합니다. **공식** 표시가 붙은 패키지는 nabi-lang 조직에서 공개하며 도구 모음에 함께 들어 있어, 그 패키지를 쓰는 프로그램은 첫 실행에서 패키지가 추가됩니다. **bin** 표시가 붙은 패키지에는 실행 파일이 있으며, `nabi install <이름>`으로 설치합니다.

더 보기: 가이드 11장의 [패키지 레지스트리](https://docs.nabi-lang.org/latest/ko/learn/11-modules-packages).

## 패키지 공개

```sh
nabi login                # 계정 페이지에서 만든 토큰
nabi publish --dry-run    # index 항목만 출력하고, 아무것도 내보내지 않습니다
nabi publish
nabi yank <이름>@0.3.1    # 새 의존성 해소는 건너뛰고, 기존 lock은 그대로 작동합니다
```

실수로 공개한 버전은 공개하고 72시간 동안, 다른 패키지가 의존하지 않는 한 삭제할 수 있습니다. [계정 페이지](/ko/me#versions)에서 지우거나, `DELETE /api/v1/packages/<이름>/<버전>`을 씁니다([API 참조](/ko/api#버전-삭제)). 그 버전 번호는 다시 쓸 수 없습니다. 그 뒤에는 철회하십시오.

아직 누구나 공개할 수는 없습니다. 토큰과 신뢰할 수 있는 게시자는 당분간 레지스트리 관리자의 것입니다. 토큰은 [계정 페이지](/ko/me)에서 만들고, 패키지 소유자는 거기서 다른 소유자를 초대하고 신뢰할 수 있는 게시자를 추가합니다. 이름은 [이용 정책](/ko/policy) 안에서 먼저 쓰는 사람의 것입니다.

가이드의 [기능과 공개](https://docs.nabi-lang.org/latest/ko/learn/18-features-and-publishing)에 더 있습니다.

- 패키지에 필요한 것, `nabi login`, `nabi publish`, 이름과 소유자, 레지스트리가 만드는 API 문서, `nabi yank`
- 신뢰할 수 있는 게시(trusted publishing): 저장한 토큰 없이 GitHub Actions에서 공개하는 법과 복사해 쓸 워크플로
- API를 안정적으로 유지하기: `#[deprecated]`, `#[non_exhaustive]`, `#[sealed]`

## 레지스트리 API

패키지 정보, README, 소스 보관본, 문서는 누구나, 어느 출처에서든 NABION이나 JSON으로 읽을 수 있습니다. [API 참조](/ko/api)를 보십시오. 각 패키지에는 README에 넣을 최신 버전 배지도 `/packages/<이름>/badge.svg`에 있습니다.
