const yearNode = document.getElementById("year");
if (yearNode) yearNode.textContent = new Date().getFullYear().toString();

const lightbox = document.getElementById("lightbox");
const lightboxImage = lightbox?.querySelector("img");
const closeButton = lightbox?.querySelector(".lightbox-close");
const shots = document.querySelectorAll(".shot");

shots.forEach((shot) => {
  shot.addEventListener("click", () => {
    const src = shot.getAttribute("data-full");
    if (!src || !lightbox || !lightboxImage) return;
    lightboxImage.src = src;
    lightbox.showModal();
  });
});

closeButton?.addEventListener("click", () => {
  lightbox?.close();
});

lightbox?.addEventListener("click", (event) => {
  const rect = lightbox.getBoundingClientRect();
  const clickedOutside =
    event.clientX < rect.left ||
    event.clientX > rect.right ||
    event.clientY < rect.top ||
    event.clientY > rect.bottom;

  if (clickedOutside) {
    lightbox.close();
  }
});
