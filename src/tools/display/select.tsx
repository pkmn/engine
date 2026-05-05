/** @license MIT modified from Pixabay's https://github.com/Pixabay/JavaScript-autoComplete */
import {Fragment} from './dom';

const FRAME_MS = 20;
// const DELAY_MS = 150;
const HIDE_MS = 350;

export const Select = ({options, unmount, placeholder, render}: {
  options: string[];
  unmount?: Promise<void>;
  placeholder?: string;
  render?: (option: string, search: string) => JSX.Element;
}) => {
  const input = <input type='text'
    name='select'
    className='select'
    autoComplete='off'
    placeholder={placeholder} /> as HTMLInputElement;
  const container = <div className='select options' /> as HTMLDivElement;

  render ||= option => input.value
    // ? <span dangerouslySetInnerHTML={{__html: searcher.highlight(option)}}></span>
    ? <>{option}</>
    : <>{option}</>;

  let maxHeight = 0;
  let offsetHeight = 0;
  let last = '';

  // const searcher = new FuzzySearch({
  //   source: options,
  //   token_field_min_length: 1,
  //   sorter: (a: any, b: any) => b.score - a.score,
  // });

  const onResize = () => {
    console.debug('onResize');
    const rect = input.getBoundingClientRect();
    container.style.left = `${Math.round(rect.left + document.documentElement.scrollLeft)}px`;
    container.style.top = `${Math.round(rect.bottom + document.documentElement.scrollTop + 1)}px`;
    container.style.width = `${Math.round(rect.right - rect.left)}px`; // outerWidth
  };
  window.addEventListener('resize', onResize);
  document.body.appendChild(container);

  const update = (next?: HTMLElement | null) => {
    console.debug('update', next);
    onResize();

    container.style.display = 'block';
    if (!maxHeight) maxHeight = parseInt((getComputedStyle(container, null)).maxHeight);
    if (!offsetHeight) {
      offsetHeight = (container.querySelector('.option') as HTMLElement).offsetHeight;
    }
    if (offsetHeight) {
      if (!next) {
        container.scrollTop = 0;
      } else {
        const scrollTop = container.scrollTop;
        const selectionTop =
          next.getBoundingClientRect().top - container.getBoundingClientRect().top;
        if (selectionTop + offsetHeight - maxHeight > 0) {
          container.scrollTop = selectionTop + offsetHeight + scrollTop - maxHeight;
        } else if (selectionTop < 0) {
          container.scrollTop = selectionTop + scrollTop;
        }
      }
    }
  };

  const cache: {[val: string]: string[]} = {};
  const suggest = (data: string[]) => {
    const val = input.value;
    cache[val] = data;
    if (data.length) {
      const children: Node[] = [];
      for (const option of data) {
        children.push(<div className='select option' data-value={option}>
          {render(option, val)}
        </div>);
      }
      container.replaceChildren(...children);
      console.debug('suggest');
      update();
    } else {
      container.style.display = 'none';
    }
  };

  const live = (e: Event, cls: string) => {
    let found = false;
    let element = e.target as HTMLElement | null;
    while (element && !(found = element.classList.contains(cls))) element = element.parentElement;
    return found ? element : undefined;
  };

  container.addEventListener('mouseleave', e => {
    if (!live(e, '.option')) return;
    console.debug('mouseleave');
    const selected = container.querySelector('.select.option.selected') as HTMLElement;
    if (selected) setTimeout(() => selected.classList.remove('selected'), FRAME_MS);
  });

  container.addEventListener('mouseover', e => {
    const element = live(e, '.option');
    if (!element) return;
    console.debug('mouseover');
    const selected = container.querySelector('.select.option.selected') as HTMLElement;
    if (selected) setTimeout(() => selected.classList.remove('selected'), FRAME_MS);
    element.classList.add('selected');
  });

  container.addEventListener('mousedown', e => {
    const element = live(e, '.option');
    if (!element) return;
    input.value = element.dataset.value!;
    console.debug('mousedown ON SELECT', input.value);
    // TODO ON SELECT
    container.style.display = 'none';
  });

  input.addEventListener('blur', () => {
    console.debug('blur');
    if (!document.querySelector('.select.options:hover')) {
      console.debug('sup 1');
      last = input.value;
      container.style.display = 'none';
      // hide suggestions on fast input
      setTimeout(() => { container.style.display = 'none'; }, HIDE_MS);
    } else if (input !== document.activeElement) {
      console.debug('sup 2', document.activeElement);
      setTimeout(() => input.focus(), FRAME_MS);
    }
  });

  input.addEventListener('keydown', e => {
    const selected = container.querySelector('.select.option.selected') as HTMLElement;
    console.debug('keydown', e.code, selected);
    if ((e.code === 'ArrowDown' || e.code === 'ArrowUp') && container.innerHTML) {
      let next: HTMLElement | null = null;
      if (!selected) {
        next = (e.code === 'ArrowDown'
          ? container.firstElementChild
          : container.lastElementChild) as HTMLElement;
        next.classList.add('selected');
        console.debug('A', next);
        input.value = next.dataset.value!;
      } else {
        next = (e.code === 'ArrowDown'
          ? selected.nextElementSibling
          : selected.previousElementSibling) as HTMLElement;
        selected.classList.remove('selected');
        if (next) {
          console.debug('B', next);
          next.classList.add('selected');
          input.value = next.dataset.value!;
        } else {
          console.debug('C', next);
          input.value = last;
        }
      }
      update(next);
      return false;
    } else if (e.code === 'Escape') {
      console.debug('D', last);
      input.value = last;
      container.style.display = 'none';
    } else if (e.code === 'Enter' || e.code === 'Tab') {
      if (selected && container.style.display !== 'none') {
        console.debug('keydown ON SELECT', selected.dataset.val);
        // TODO ON SELECT selected.dataset.val
        setTimeout(() => { container.style.display = 'none'; }, FRAME_MS);
      }
    }
    return true;
  });

  // let timer: number;
  const keys =
    ['End', 'Home', 'ArrowLeft', 'ArrowUp', 'ArrowRight', 'ArrowDown', 'Enter', 'Escape'];
  input.addEventListener('keyup', e => {
    console.debug('keyup');
    if (!e.code || !keys.includes(e.code)) {
      const val = input.value;
      if (val !== last) {
        last = val;
        // clearTimeout(timer);
        if (cache) if (val in cache) return suggest(cache[val]);
        // timer = setTimeout(() => suggest(searcher.search(val)), DELAY_MS) as any as number;
      }
    }
  });

  input.addEventListener('focus', () => {
    console.debug('focus');
    if (!container.innerHTML || container.style.display === 'none') suggest(options);
  });

  // eslint-disable-next-line @typescript-eslint/no-floating-promises
  unmount?.finally(() => {
    window.removeEventListener('resize', onResize);
    document.body.removeChild(container);
  });

  return input as unknown as JSX.Element; // FIXME onSelect = onChange? input.value?
};
