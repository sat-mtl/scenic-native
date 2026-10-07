/*{
  "CREDIT": "Scenic",
  "CATEGORIES": [ "Utility" ],
  "DESCRIPTION": "Scenic source hub: passthrough",
  "INPUTS": [ { "NAME": "inputImage", "TYPE": "image" } ]
}*/

void main()
{
  gl_FragColor = IMG_THIS_PIXEL(inputImage);
}
