/** @license MIT modified from Vadim Demedes's https://github.com/vadimdemedes/dom-chef */

declare global {
  namespace JSX {
    type Element = HTMLElement | DocumentFragment;
    interface IntrinsicElements {
      [elemName: string]: Record<string, unknown>;
    }
  }
}

type Child = Node | string | number | boolean | null | undefined | Child[];

type DocumentFragmentFunction = (props?: any) => DocumentFragment;
type ElementFunction = (props?: any) => HTMLElement;

// https://github.com/preactjs/preact/blob/1bbd687c/src/constants.js#L3
const IS_NON_DIMENSIONAL = /acit|ex(?:s|g|n|p|$)|rph|grid|ows|mnc|ntw|ine[ch]|zoo|^ord|itera/i;

const setCSSProps = (element: HTMLElement, style: CSSStyleDeclaration) => {
  for (const [name, value] of Object.entries(style)) {
    if (name.startsWith('-')) {
      element.style.setProperty(name, value);
    } else if (typeof value === 'number' && !IS_NON_DIMENSIONAL.test(name)) {
      element.style[name as any] = `${value as string}px`;
    } else {
      element.style[name as any] = value;
    }
  }
};

const setAttribute = (element: HTMLElement, name: string, value: string) => {
  if (value !== undefined && value !== null) element.setAttribute(name, value);
};

const addChildren = (parent: Node, children: Child[]) => {
  for (const child of children) {
    if (child instanceof Node) {
      parent.appendChild(child);
    } else if (Array.isArray(child)) {
      addChildren(parent, child);
    } else if (typeof child !== 'boolean' && typeof child !== 'undefined' && child !== null) {
      parent.appendChild(document.createTextNode(String(child)));
    }
  }
};

// https://github.com/facebook/react/blob/3f899089/packages/react-dom/src/shared/DOMProperty.js#L288-L322
const FALSIFIABLE_ATTRIBUTES = ['contentEditable', 'draggable', 'spellCheck', 'value'];

export function h<K extends keyof HTMLElementTagNameMap>(
  type: K,
  attributes?: any,
  ...children: Child[]
): HTMLElementTagNameMap[K];
export function h(
  type: DocumentFragmentFunction,
  attributes?: any,
  ...children: Child[]
): DocumentFragment;
export function h<T extends HTMLElement>(
  type: (props: any) => T,
  attributes?: any,
  ...children: Child[]
): T;
export function h(
  type: string,
  attributes?: any,
  ...children: Child[]
): HTMLElement;
export function h(
  type: DocumentFragmentFunction | ElementFunction | string,
  attributes?: any,
  ...children: Child[]
): JSX.Element {
  if (typeof type !== 'string') {
    const element = type(attributes);
    addChildren(element, children);
    return element;
  }

  const element = document.createElement(type);
  addChildren(element, children);
  if (!attributes) return element;

  for (let [name, value] of Object.entries(attributes)) {
    if (name === 'htmlFor') name = 'for';

    if (name === 'class' || name === 'className') {
      const existingClassname = element.getAttribute('class') ?? '';
      setAttribute(element, 'class', (existingClassname + ' ' + String(value)).trim());
    } else if (name === 'style') {
      setCSSProps(element, value as CSSStyleDeclaration);
    } else if (name.startsWith('on')) {
      const eventName = name.slice(2).toLowerCase().replace(/^-/, '');
      element.addEventListener(eventName, value as EventListenerOrEventListenerObject);
    } else if (name === 'dangerouslySetInnerHTML' && value && (value as any).__html) {
      element.innerHTML = (value as any).__html;
    } else if (name !== 'key' && (FALSIFIABLE_ATTRIBUTES.includes(name) || value !== false)) {
      setAttribute(element, name, value === true ? '' : String(value));
    }
  }

  return element;
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export const Fragment = (unused?: any) => document.createDocumentFragment();
